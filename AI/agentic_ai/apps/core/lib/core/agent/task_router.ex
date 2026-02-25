defmodule Core.Agent.TaskRouter do
  @moduledoc """
  사용자 요청을 분석하여 적절한 Worker를 선택합니다.

  키워드 기반 매칭과 Worker의 능력(description, enabled_tools)을
  분석하여 가장 적합한 Worker를 반환합니다.
  """

  require Logger
  alias Core.Schema.Agent

  # 도메인별 키워드 매핑
  @domain_keywords %{
    calculator: [
      "계산",
      "더하기",
      "빼기",
      "곱하기",
      "나누기",
      "수학",
      "숫자",
      "평균",
      "합계",
      "통계",
      "단위",
      "변환",
      "+",
      "-",
      "*",
      "/",
      "="
    ],
    code: [
      "코드",
      "프로그램",
      "함수",
      "실행",
      "디버그",
      "테스트",
      "리팩토링",
      "구현"
    ],
    web_search: [
      "검색",
      "찾아",
      "알려",
      "최신",
      "뉴스",
      "정보",
      "조사"
    ]
  }

  @doc """
  사용자 요청에 가장 적합한 Worker를 선택합니다.

  ## Parameters

    - `user_request` - 사용자 요청 문자열
    - `workers` - 사용 가능한 Worker 에이전트 목록 (%Agent{} 구조체)

  ## Returns

    - `{:ok, worker}` - 선택된 Worker
    - `{:error, :no_workers_available}` - 사용 가능한 Worker가 없음

  ## Examples

      iex> TaskRouter.select_worker("2 + 2를 계산해줘", workers)
      {:ok, %Agent{name: "calculator_worker", ...}}

      iex> TaskRouter.select_worker("최신 뉴스 검색해줘", workers)
      {:ok, %Agent{name: "general_worker", ...}}
  """
  @spec select_worker(String.t(), list(Agent.t())) ::
          {:ok, Agent.t()} | {:error, :no_workers_available}
  def select_worker(_user_request, []) do
    Logger.warning("No workers available for task routing")
    {:error, :no_workers_available}
  end

  def select_worker(user_request, workers) do
    Logger.info("Routing task: #{user_request}")
    Logger.info("Available workers: #{inspect(Enum.map(workers, & &1.name))}")

    # Calculate match score for each worker
    scored_workers =
      Enum.map(workers, fn worker ->
        score = calculate_match_score(user_request, worker)
        {worker, score}
      end)

    # Sort by score (highest first)
    sorted_workers = Enum.sort_by(scored_workers, fn {_worker, score} -> score end, :desc)

    case sorted_workers do
      [{worker, score} | _] ->
        Logger.info("Selected worker: #{worker.name} (score: #{score})")
        {:ok, worker}

      [] ->
        {:error, :no_workers_available}
    end
  end

  # 비공개 함수들

  defp calculate_match_score(user_request, worker) do
    description_score = calculate_description_score(user_request, worker.description)
    tools_score = calculate_tools_score(user_request, worker.enabled_tools)
    name_score = calculate_name_score(user_request, worker.name)

    # 가중 평균
    description_score * 0.5 + tools_score * 0.3 + name_score * 0.2
  end

  defp calculate_description_score(user_request, description) do
    when_not_empty(description, fn desc ->
      request_lower = String.downcase(user_request)
      desc_lower = String.downcase(desc)

      # 키워드 일치 개수 계산
      keywords = extract_keywords(desc_lower)

      matches =
        Enum.count(keywords, fn keyword ->
          String.contains?(request_lower, keyword)
        end)

      if length(keywords) > 0 do
        matches / length(keywords) * 100
      else
        0
      end
    end)
  end

  defp calculate_tools_score(user_request, enabled_tools) do
    request_lower = String.downcase(user_request)

    # 요청이 도메인 키워드와 일치하는지 확인
    matching_domains =
      Enum.filter(@domain_keywords, fn {_domain, keywords} ->
        Enum.any?(keywords, &String.contains?(request_lower, &1))
      end)

    if matching_domains == [] do
      0
    else
      # Worker가 일치하는 도메인의 도구를 가지고 있는지 확인
      domain_names = Enum.map(matching_domains, fn {domain, _} -> to_string(domain) end)

      tool_matches =
        Enum.count(enabled_tools, fn tool ->
          Enum.any?(domain_names, &String.contains?(tool, &1))
        end)

      if length(enabled_tools) > 0 do
        tool_matches / length(enabled_tools) * 100
      else
        0
      end
    end
  end

  defp calculate_name_score(user_request, name) do
    request_lower = String.downcase(user_request)
    name_lower = String.downcase(name)

    # 이름에서 Worker 타입 추출 (예: "calculator_worker"에서 "calculator")
    worker_type =
      name_lower
      |> String.replace("_worker", "")
      |> String.replace("_agent", "")

    # Worker 타입 키워드가 일치하는지 확인
    domain_keywords = Map.get(@domain_keywords, String.to_atom(worker_type), [])

    matches = Enum.count(domain_keywords, &String.contains?(request_lower, &1))

    if length(domain_keywords) > 0 do
      matches / length(domain_keywords) * 100
    else
      0
    end
  end

  defp extract_keywords(text) do
    text
    |> String.split(~r/\s+/, trim: true)
    |> Enum.filter(&(String.length(&1) > 2))
    |> Enum.uniq()
  end

  defp when_not_empty(value, func) do
    if value && value != "" do
      func.(value)
    else
      0
    end
  end
end
