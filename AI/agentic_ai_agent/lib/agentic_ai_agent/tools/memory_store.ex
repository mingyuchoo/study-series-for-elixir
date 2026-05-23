defmodule AgenticAiAgent.Tools.MemoryStore do
  @moduledoc """
  Persist a fact in the agent's long-term memory store. The agent should
  use this sparingly — only for durable, user-confirmed facts (preferences,
  long-running goals, summaries of completed tasks), never speculative
  intermediate reasoning.
  """

  @behaviour AgenticAiAgent.Tool

  alias AgenticAiAgent.Memory

  @impl true
  def name, do: "memory_store"

  @impl true
  def description,
    do:
      "Save a durable fact to the agent's long-term memory. Use only for confirmed, reusable knowledge (user preferences, completed task summaries). Returns the new memory's id."

  @impl true
  def input_schema do
    %{
      "type" => "object",
      "required" => ["content"],
      "properties" => %{
        "content" => %{"type" => "string", "minLength" => 1, "maxLength" => 4000},
        "kind" => %{"type" => "string", "enum" => Memory.Memory.kinds()},
        "source" => %{"type" => "string", "maxLength" => 200},
        "sensitivity" =>
          %{"type" => "string", "enum" => Memory.Memory.sensitivities()},
        "confidence" => %{"type" => "number", "minimum" => 0, "maximum" => 1},
        "retention_days" => %{
          "type" => "integer",
          "minimum" => 1,
          "maximum" => 36500,
          "description" => "If set together with deletion_rule=ttl, the row is auto-deleted after this many days."
        },
        "update_rule" => %{
          "type" => "string",
          "enum" => ~w(append_only overwrite_by_source overwrite_by_id),
          "description" => "How to handle a duplicate. Default append_only."
        },
        "deletion_rule" => %{
          "type" => "string",
          "enum" => ~w(manual ttl on_request),
          "description" => "Lifecycle policy. Default manual."
        }
      }
    }
  end

  @impl true
  def output_schema do
    %{
      "type" => "object",
      "required" => ["id"],
      "properties" => %{
        "id" => %{"type" => "string"},
        "kind" => %{"type" => "string"}
      }
    }
  end

  # Writing to memory is medium risk — the agent can persist false beliefs.
  @impl true
  def risk_level, do: :medium

  @impl true
  def side_effects do
    [
      "Persists a row in the `memories` table.",
      "Embeds the content via the configured Embeddings adapter.",
      "May overwrite an existing row when update_rule is overwrite_by_*."
    ]
  end

  @impl true
  def failure_modes, do: ["tool_invalid_input"]

  # Memory writes are not idempotent across overwrite_by_source — skip retry.
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
  def call(%{"content" => content} = input) do
    opts =
      input
      |> Map.take(~w(kind source sensitivity confidence retention_days update_rule deletion_rule))
      |> Enum.map(fn {k, v} -> {String.to_atom(k), v} end)

    case Memory.remember(content, opts) do
      {:ok, mem} ->
        {:ok,
         %{
           "id" => mem.id,
           "kind" => mem.kind,
           "update_rule" => mem.update_rule,
           "deletion_rule" => mem.deletion_rule
         }}

      {:error, reason} ->
        {:error, format_reason(reason)}
    end
  end

  defp format_reason({:missing_config, key}),
    do: "embeddings not configured (missing #{key})"

  defp format_reason(reason), do: inspect(reason)
end
