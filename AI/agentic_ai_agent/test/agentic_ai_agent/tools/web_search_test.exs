defmodule AgenticAiAgent.Tools.WebSearchTest do
  use ExUnit.Case, async: false

  alias AgenticAiAgent.Tools.WebSearch

  setup do
    original = Application.get_env(:agentic_ai_agent, WebSearch)

    on_exit(fn ->
      if is_nil(original) do
        Application.delete_env(:agentic_ai_agent, WebSearch)
      else
        Application.put_env(:agentic_ai_agent, WebSearch, original)
      end
    end)

    :ok
  end

  test "requires a Firecrawl API key" do
    Application.put_env(:agentic_ai_agent, WebSearch, api_key: "")

    assert {:error, "missing FIRECRAWL_API_KEY"} =
             WebSearch.call(%{"query" => "Seoul weather today"})
  end

  test "posts Firecrawl search payload and maps v2 web results into the tool output schema" do
    parent = self()

    http_client = fn endpoint, opts ->
      send(parent, {:request, endpoint, opts})

      {:ok,
       %{
         status: 200,
         body: %{
           "success" => true,
           "data" => %{
             "web" => [
               %{
                 "title" => "Seoul weather",
                 "url" => "https://example.com/weather",
                 "description" => "Current weather in Seoul.",
                 "markdown" => "Forecast and hourly details."
               }
             ]
           }
         }
       }}
    end

    Application.put_env(:agentic_ai_agent, WebSearch,
      api_key: "test-token",
      endpoint: "https://search.test/v2/search",
      http_client: http_client
    )

    assert {:ok,
            %{
              "query" => "Seoul weather today",
              "results" => [
                %{
                  "title" => "Seoul weather",
                  "url" => "https://example.com/weather",
                  "snippet" => "Current weather in Seoul.\nForecast and hourly details."
                }
              ]
            }} =
             WebSearch.call(%{
               "query" => "Seoul weather today",
               "max_results" => 1,
               "country" => "KR",
               "location" => "Seoul,South Korea",
               "scrape_markdown" => true
             })

    assert_receive {:request, "https://search.test/v2/search", opts}
    assert {"authorization", "Bearer test-token"} in opts[:headers]
    assert opts[:json][:query] == "Seoul weather today"
    assert opts[:json][:limit] == 1
    assert opts[:json][:sources] == ["web"]
    assert opts[:json][:country] == "KR"
    assert opts[:json][:location] == "Seoul,South Korea"
    assert opts[:json][:scrapeOptions] == %{formats: ["markdown"]}
  end
end
