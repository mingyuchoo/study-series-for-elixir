defmodule AgenticAiAgent.Tools.WebSearch do
  @moduledoc """
  Web search via the Brave Search API.
  """

  @behaviour AgenticAiAgent.Tool

  @endpoint "https://api.search.brave.com/res/v1/web/search"
  @default_timeout_ms 8_000
  @default_max_results 5
  @max_results 20

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
        "max_results" => %{"type" => "integer", "minimum" => 1, "maximum" => 20},
        "country" => %{"type" => "string", "minLength" => 2, "maxLength" => 2},
        "search_lang" => %{"type" => "string", "minLength" => 2, "maxLength" => 2},
        "ui_lang" => %{"type" => "string", "minLength" => 2, "maxLength" => 8},
        "freshness" => %{"type" => "string"},
        "safesearch" => %{"type" => "string", "enum" => ["off", "moderate", "strict"]}
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
  def side_effects, do: ["Calls the Brave Search API."]

  @impl true
  def failure_modes, do: ["tool_network_error", "tool_timeout", "tool_invalid_input"]

  @impl true
  def retry_policy do
    %{max_retries: 2, backoff_ms: 400, retry_on: ["tool_network_error", "tool_timeout"]}
  end

  @impl true
  def call(%{"query" => query} = input) when is_binary(query) do
    max_results = input |> Map.get("max_results", @default_max_results) |> normalize_max_results()

    with {:ok, api_key} <- api_key(),
         {:ok, %{status: status, body: body}} when status in 200..299 <-
           http_client().(endpoint(),
             headers: headers(api_key),
             params: params(query, max_results, input),
             receive_timeout: @default_timeout_ms
           ),
         {:ok, body} <- decode_body(body) do
      {:ok, %{"query" => query, "results" => extract_results(body) |> Enum.take(max_results)}}
    else
      {:ok, %{status: status, body: body}} ->
        {:error, brave_error(status, body)}

      {:error, %{__exception__: true} = exc} ->
        {:error, Exception.message(exc)}

      {:error, reason} when is_binary(reason) ->
        {:error, reason}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  def call(_), do: {:error, "missing or invalid query"}

  defp api_key do
    case config()[:api_key] || System.get_env("BRAVE_SEARCH_API_KEY") do
      key when is_binary(key) and key != "" -> {:ok, key}
      _ -> {:error, "missing BRAVE_SEARCH_API_KEY"}
    end
  end

  defp config, do: Application.get_env(:agentic_ai_agent, __MODULE__, [])

  defp endpoint, do: config()[:endpoint] || @endpoint

  defp http_client, do: config()[:http_client] || (&Req.get/2)

  defp headers(api_key) do
    [
      {"accept", "application/json"},
      {"x-subscription-token", api_key}
    ]
  end

  defp params(query, max_results, input) do
    [
      q: query,
      count: max_results,
      safesearch: Map.get(input, "safesearch", "moderate"),
      text_decorations: false,
      spellcheck: true
    ]
    |> put_optional(:country, Map.get(input, "country"))
    |> put_optional(:search_lang, Map.get(input, "search_lang"))
    |> put_optional(:ui_lang, Map.get(input, "ui_lang"))
    |> put_optional(:freshness, Map.get(input, "freshness"))
  end

  defp put_optional(params, _key, nil), do: params
  defp put_optional(params, _key, ""), do: params
  defp put_optional(params, key, value), do: Keyword.put(params, key, value)

  defp normalize_max_results(value) when is_integer(value) do
    value |> max(1) |> min(@max_results)
  end

  defp normalize_max_results(_), do: @default_max_results

  defp decode_body(body) when is_map(body), do: {:ok, body}

  defp decode_body(body) when is_binary(body) do
    case String.trim(body) do
      "" ->
        {:error, "search endpoint returned an empty body"}

      json ->
        case Jason.decode(json) do
          {:ok, decoded} ->
            {:ok, decoded}

          {:error, error} ->
            {:error, "search endpoint returned invalid JSON: #{Exception.message(error)}"}
        end
    end
  end

  defp decode_body(_), do: {:error, "search endpoint returned an unsupported body"}

  defp brave_error(status, body) do
    with {:ok, decoded} <- decode_body(body),
         message when is_binary(message) <-
           get_in(decoded, ["error", "detail"]) || decoded["message"] do
      "search endpoint returned HTTP #{status}: #{message}"
    else
      _ -> "search endpoint returned HTTP #{status}"
    end
  end

  defp extract_results(body) do
    body
    |> get_in(["web", "results"])
    |> List.wrap()
    |> Enum.map(&normalize_result/1)
    |> Enum.reject(&(&1["title"] == "" or &1["url"] == ""))
  end

  defp normalize_result(%{} = result) do
    description = Map.get(result, "description", "")
    extra_snippets = Map.get(result, "extra_snippets", [])
    snippet = [description | extra_snippets] |> Enum.filter(&is_binary/1) |> Enum.join("\n")

    %{
      "title" => Map.get(result, "title", ""),
      "url" => Map.get(result, "url", ""),
      "snippet" => snippet
    }
  end

  defp normalize_result(_), do: %{"title" => "", "url" => "", "snippet" => ""}
end
