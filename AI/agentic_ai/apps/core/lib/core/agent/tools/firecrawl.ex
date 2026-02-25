defmodule Core.Agent.Tools.Firecrawl do
  @moduledoc """
  Firecrawl API를 사용한 웹 스크래핑 및 검색 도구입니다.

  ## 환경 변수

    - `FIRECRAWL_API_KEY`: Firecrawl API 키 (필수)

  ## 제공 도구

    - `firecrawl_scrape`: URL에서 콘텐츠를 추출하여 마크다운으로 변환
    - `firecrawl_search`: 웹 검색 수행
  """

  @base_url "https://api.firecrawl.dev"

  # 도구 정의

  def definition("firecrawl_scrape") do
    %{
      name: "firecrawl_scrape",
      description: "웹 페이지의 콘텐츠를 스크래핑하여 마크다운으로 변환합니다. 뉴스 기사, 블로그 포스트, 문서 페이지 등의 내용을 가져올 때 사용합니다.",
      parameters: %{
        type: "object",
        properties: %{
          url: %{
            type: "string",
            description: "스크래핑할 웹 페이지 URL"
          }
        },
        required: ["url"]
      }
    }
  end

  def definition("firecrawl_search") do
    %{
      name: "firecrawl_search",
      description: "웹에서 정보를 검색하고 관련 결과를 반환합니다. 최신 정보나 특정 주제에 대한 검색에 사용합니다.",
      parameters: %{
        type: "object",
        properties: %{
          query: %{
            type: "string",
            description: "검색어"
          },
          limit: %{
            type: "integer",
            description: "반환할 결과 수 (기본값: 5, 최대: 10)"
          }
        },
        required: ["query"]
      }
    }
  end

  def definition(_), do: nil

  # 도구 실행

  def execute("firecrawl_scrape", %{"url" => url}) do
    case get_api_key() do
      {:ok, api_key} ->
        scrape_url(api_key, url)

      {:error, reason} ->
        {:error, reason}
    end
  end

  def execute("firecrawl_search", args) do
    query = Map.get(args, "query")
    limit = Map.get(args, "limit", 5) |> min(10)

    case get_api_key() do
      {:ok, api_key} ->
        search_web(api_key, query, limit)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # 비공개 함수들

  defp get_api_key do
    case System.get_env("FIRECRAWL_API_KEY") do
      nil -> {:error, "FIRECRAWL_API_KEY 환경 변수가 설정되지 않았습니다"}
      "" -> {:error, "FIRECRAWL_API_KEY 환경 변수가 비어있습니다"}
      key -> {:ok, key}
    end
  end

  defp scrape_url(api_key, url) do
    request_body = %{
      url: url,
      formats: ["markdown"]
    }

    case make_request(api_key, "/v1/scrape", request_body) do
      {:ok, %{"success" => true, "data" => data}} ->
        {:ok,
         %{
           url: url,
           title: Map.get(data, "metadata", %{}) |> Map.get("title", ""),
           content: Map.get(data, "markdown", ""),
           word_count: count_words(Map.get(data, "markdown", ""))
         }}

      {:ok, %{"success" => false, "error" => error}} ->
        {:error, "스크래핑 실패: #{error}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp search_web(api_key, query, limit) do
    request_body = %{
      query: query,
      limit: limit
    }

    case make_request(api_key, "/v1/search", request_body) do
      {:ok, %{"success" => true, "data" => results}} when is_list(results) ->
        formatted_results =
          Enum.map(results, fn result ->
            %{
              title: Map.get(result, "title", ""),
              url: Map.get(result, "url", ""),
              description: Map.get(result, "description", ""),
              content: Map.get(result, "markdown", "") |> String.slice(0, 500)
            }
          end)

        {:ok,
         %{
           query: query,
           total_results: length(formatted_results),
           results: formatted_results
         }}

      {:ok, %{"success" => false, "error" => error}} ->
        {:error, "검색 실패: #{error}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp make_request(api_key, endpoint, body) do
    url = @base_url <> endpoint

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"}
    ]

    case Req.post(url, json: body, headers: headers, receive_timeout: 30_000) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: 401}} ->
        {:error, "API 인증 실패: API 키를 확인하세요"}

      {:ok, %{status: 402}} ->
        {:error, "API 크레딧이 부족합니다. Firecrawl 대시보드를 확인하세요"}

      {:ok, %{status: 429}} ->
        {:error, "요청 한도 초과. 잠시 후 다시 시도하세요"}

      {:ok, %{status: status, body: body}} ->
        error_msg = get_in(body, ["error"]) || "HTTP #{status}"
        {:error, "요청 실패: #{error_msg}"}

      {:error, %Req.TransportError{reason: :timeout}} ->
        {:error, "요청 시간 초과. 페이지가 너무 크거나 서버가 응답하지 않습니다"}

      {:error, reason} ->
        {:error, "네트워크 오류: #{inspect(reason)}"}
    end
  end

  defp count_words(nil), do: 0
  defp count_words(""), do: 0

  defp count_words(text) do
    text
    |> String.split(~r/\s+/, trim: true)
    |> length()
  end
end
