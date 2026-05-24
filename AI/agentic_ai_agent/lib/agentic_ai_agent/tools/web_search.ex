defmodule AgenticAiAgent.Tools.WebSearch do
  @moduledoc """
  Web search via the Firecrawl Search API.
  """

  @behaviour AgenticAiAgent.Tool

  @endpoint "https://api.firecrawl.dev/v2/search"
  @default_timeout_ms 60_000
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
        "location" => %{"type" => "string"},
        "country" => %{"type" => "string", "minLength" => 2, "maxLength" => 2},
        "freshness" => %{"type" => "string"},
        "tbs" => %{"type" => "string"},
        "include_domains" => %{"type" => "array", "items" => %{"type" => "string"}},
        "exclude_domains" => %{"type" => "array", "items" => %{"type" => "string"}},
        "scrape_markdown" => %{"type" => "boolean"},
        "timeout_ms" => %{"type" => "integer", "minimum" => 1_000, "maximum" => 120_000}
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
  def side_effects, do: ["Calls the Firecrawl Search API."]

  @impl true
  def failure_modes, do: ["tool_network_error", "tool_timeout", "tool_invalid_input"]

  @impl true
  def retry_policy do
    %{max_retries: 2, backoff_ms: 400, retry_on: ["tool_network_error", "tool_timeout"]}
  end

  @impl true
  def call(%{"query" => query} = input) when is_binary(query) do
    max_results = input |> Map.get("max_results", @default_max_results) |> normalize_max_results()
    timeout = input |> Map.get("timeout_ms", @default_timeout_ms) |> normalize_timeout()

    with {:ok, api_key} <- api_key(),
         {:ok, %{status: status, body: body}} when status in 200..299 <-
           http_client().(endpoint(),
             headers: headers(api_key),
             json: payload(query, max_results, timeout, input),
             receive_timeout: timeout
           ),
         {:ok, body} <- decode_body(body) do
      {:ok, %{"query" => query, "results" => extract_results(body) |> Enum.take(max_results)}}
    else
      {:ok, %{status: status, body: body}} ->
        {:error, firecrawl_error(status, body)}

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
    case config()[:api_key] || System.get_env("FIRECRAWL_API_KEY") do
      key when is_binary(key) and key != "" -> {:ok, key}
      _ -> {:error, "missing FIRECRAWL_API_KEY"}
    end
  end

  defp config, do: Application.get_env(:agentic_ai_agent, __MODULE__, [])

  defp endpoint, do: config()[:endpoint] || @endpoint

  defp http_client, do: config()[:http_client] || (&Req.post/2)

  defp headers(api_key) do
    [
      {"accept", "application/json"},
      {"authorization", "Bearer #{api_key}"}
    ]
  end

  defp payload(query, max_results, timeout, input) do
    %{
      query: query,
      limit: max_results,
      sources: ["web"],
      timeout: timeout,
      ignoreInvalidURLs: true
    }
    |> put_optional(:country, Map.get(input, "country"))
    |> put_optional(:location, Map.get(input, "location"))
    |> put_optional(:tbs, Map.get(input, "tbs") || Map.get(input, "freshness"))
    |> put_optional(:includeDomains, Map.get(input, "include_domains"))
    |> put_optional(:excludeDomains, Map.get(input, "exclude_domains"))
    |> maybe_put_scrape_options(Map.get(input, "scrape_markdown", false))
  end

  defp put_optional(payload, _key, nil), do: payload
  defp put_optional(payload, _key, ""), do: payload
  defp put_optional(payload, _key, []), do: payload
  defp put_optional(payload, key, value), do: Map.put(payload, key, value)

  defp maybe_put_scrape_options(payload, true),
    do: Map.put(payload, :scrapeOptions, %{formats: ["markdown"]})

  defp maybe_put_scrape_options(payload, _), do: payload

  defp normalize_max_results(value) when is_integer(value) do
    value |> max(1) |> min(@max_results)
  end

  defp normalize_max_results(_), do: @default_max_results

  defp normalize_timeout(value) when is_integer(value) do
    value |> max(1_000) |> min(120_000)
  end

  defp normalize_timeout(_), do: @default_timeout_ms

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

  defp firecrawl_error(status, body) do
    with {:ok, decoded} <- decode_body(body),
         message when is_binary(message) <-
           decoded["error"] || decoded["message"] || decoded["warning"] do
      "search endpoint returned HTTP #{status}: #{message}"
    else
      _ -> "search endpoint returned HTTP #{status}"
    end
  end

  defp extract_results(body) do
    body
    |> firecrawl_results()
    |> List.wrap()
    |> Enum.map(&normalize_result/1)
    |> Enum.reject(&(&1["title"] == "" or &1["url"] == ""))
  end

  defp firecrawl_results(%{"data" => %{"web" => results}}) when is_list(results), do: results
  defp firecrawl_results(%{"data" => results}) when is_list(results), do: results
  defp firecrawl_results(_), do: []

  defp normalize_result(%{} = result) do
    description = Map.get(result, "description", "")
    markdown = Map.get(result, "markdown", "")

    snippet =
      [description, markdown]
      |> Enum.filter(&is_binary/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n")

    %{
      "title" => Map.get(result, "title", ""),
      "url" => Map.get(result, "url", ""),
      "snippet" => snippet
    }
  end

  defp normalize_result(_), do: %{"title" => "", "url" => "", "snippet" => ""}
end
