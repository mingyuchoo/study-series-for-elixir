defmodule AgenticAiAgent.Tools.WebSearch do
  @moduledoc """
  Lightweight web search via DuckDuckGo's Instant Answer API. No API key
  required, but coverage is limited — meant as a placeholder until a real
  search provider (Brave/Tavily/SerpAPI) is wired in.
  """

  @behaviour AgenticAiAgent.Tool

  @endpoint "https://api.duckduckgo.com/"
  @default_timeout_ms 8_000

  @impl true
  def name, do: "web_search"

  @impl true
  def description,
    do:
      "Search the public web for a short query and return a list of result snippets. Use for fresh or general-knowledge facts."

  @impl true
  def input_schema do
    %{
      "type" => "object",
      "required" => ["query"],
      "properties" => %{
        "query" => %{"type" => "string", "minLength" => 1, "maxLength" => 500},
        "max_results" => %{"type" => "integer", "minimum" => 1, "maximum" => 20}
      }
    }
  end

  @impl true
  def output_schema do
    %{
      "type" => "object",
      "required" => ["query", "results"],
      "properties" => %{
        "query" => %{"type" => "string"},
        "results" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "required" => ["title", "url", "snippet"],
            "properties" => %{
              "title" => %{"type" => "string"},
              "url" => %{"type" => "string"},
              "snippet" => %{"type" => "string"}
            }
          }
        }
      }
    }
  end

  @impl true
  def risk_level, do: :low

  @impl true
  def side_effects, do: ["Calls a public search endpoint (DuckDuckGo Instant Answer)."]

  @impl true
  def failure_modes, do: ["tool_network_error", "tool_timeout", "tool_invalid_input"]

  @impl true
  def retry_policy do
    %{max_retries: 2, backoff_ms: 400, retry_on: ["tool_network_error", "tool_timeout"]}
  end

  @impl true
  def call(%{"query" => query} = input) when is_binary(query) do
    max_results = Map.get(input, "max_results", 5)

    params = [q: query, format: "json", no_redirect: "1", no_html: "1", skip_disambig: "1"]

    case Req.get(@endpoint, params: params, receive_timeout: @default_timeout_ms) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok,
         %{"query" => query, "results" => extract_results(body) |> Enum.take(max_results)}}

      {:ok, %{status: status}} ->
        {:error, "search endpoint returned HTTP #{status}"}

      {:error, %{__exception__: true} = exc} ->
        {:error, Exception.message(exc)}

      {:error, reason} when is_binary(reason) ->
        {:error, reason}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  def call(_), do: {:error, "missing or invalid query"}

  defp extract_results(body) do
    abstract =
      case body do
        %{"AbstractText" => text, "AbstractURL" => url, "Heading" => heading}
        when is_binary(text) and text != "" ->
          [%{"title" => heading || "", "url" => url || "", "snippet" => text}]

        _ ->
          []
      end

    related =
      body
      |> Map.get("RelatedTopics", [])
      |> Enum.flat_map(&flatten_topic/1)
      |> Enum.map(fn t ->
        %{
          "title" => Map.get(t, "Text", "") |> String.slice(0, 120),
          "url" => Map.get(t, "FirstURL", ""),
          "snippet" => Map.get(t, "Text", "")
        }
      end)
      |> Enum.reject(&(&1["url"] == "" or &1["snippet"] == ""))

    abstract ++ related
  end

  defp flatten_topic(%{"Topics" => topics}) when is_list(topics), do: topics
  defp flatten_topic(topic) when is_map(topic), do: [topic]
  defp flatten_topic(_), do: []
end
