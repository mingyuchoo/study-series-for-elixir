defmodule AgenticAiAgent.Tools.MemorySearch do
  @moduledoc """
  Semantic search over the agent's long-term memory. Use this whenever
  the user references something they told you in a previous session or
  when domain facts may have been stored.
  """

  @behaviour AgenticAiAgent.Tool

  alias AgenticAiAgent.Memory

  @impl true
  def name, do: "memory_search"

  @impl true
  def description,
    do:
      "Search the agent's long-term memory store for entries semantically similar to a query. Returns the top matches with scores."

  @impl true
  def input_schema do
    %{
      "type" => "object",
      "required" => ["query"],
      "properties" => %{
        "query" => %{"type" => "string", "minLength" => 1, "maxLength" => 1000},
        "k" => %{"type" => "integer", "minimum" => 1, "maximum" => 20},
        "kind" => %{"type" => "string", "enum" => Memory.Memory.kinds()},
        "min_score" => %{"type" => "number", "minimum" => 0, "maximum" => 1}
      }
    }
  end

  @impl true
  def output_schema do
    %{
      "type" => "object",
      "required" => ["query", "matches"],
      "properties" => %{
        "query" => %{"type" => "string"},
        "matches" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "required" => ["content", "score"],
            "properties" => %{
              "id" => %{"type" => "string"},
              "content" => %{"type" => "string"},
              "score" => %{"type" => "number"},
              "kind" => %{"type" => "string"},
              "source" => %{"type" => "string"}
            }
          }
        }
      }
    }
  end

  @impl true
  def risk_level, do: :low

  @impl true
  def side_effects, do: ["Updates last_accessed_at / access_count on every match."]

  @impl true
  def failure_modes, do: ["tool_invalid_input"]

  @impl true
  def retry_policy, do: %{max_retries: 0}

  @impl true
  def precheck(_input) do
    cfg = Application.get_env(:agentic_ai_agent, AgenticAiAgent.LLM.AzureOpenAIEmbeddings, [])

    case Keyword.get(cfg, :deployment) do
      v when v in [nil, ""] -> {:error, "embeddings deployment not configured"}
      _ -> :ok
    end
  end

  @impl true
  def call(%{"query" => query} = input) do
    opts = [
      k: Map.get(input, "k", 5),
      min_score: Map.get(input, "min_score", 0.0),
      filters: build_filters(input)
    ]

    case Memory.search(query, opts) do
      {:ok, results} ->
        matches =
          for {score, m} <- results do
            %{
              "id" => m.id,
              "content" => m.content,
              "score" => Float.round(score, 4),
              "kind" => m.kind,
              "source" => m.source
            }
          end

        {:ok, %{"query" => query, "matches" => matches}}

      {:error, reason} ->
        {:error, format_reason(reason)}
    end
  end

  defp build_filters(input) do
    case Map.get(input, "kind") do
      nil -> []
      kind -> [kind: kind]
    end
  end

  defp format_reason({:missing_config, key}),
    do: "embeddings not configured (missing #{key})"

  defp format_reason(reason), do: inspect(reason)
end
