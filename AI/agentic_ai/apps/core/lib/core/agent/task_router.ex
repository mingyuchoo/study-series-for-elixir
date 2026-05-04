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
      "조사",
      # 실시간 데이터/외부 정보 키워드
      "시세",
      "가격",
      "환율",
      "주가",
      "비트코인",
      "이더리움",
      "코인",
      "주식",
      "날씨",
      "기온",
      "지금",
      "현재",
      "오늘",
      "어제",
      "최근",
      "스크랩",
      "스크래핑",
      "url",
      "http",
      "사이트",
      "페이지",
      "웹사이트"
    ]
  }

  # 프로덕션 도구 이름 → 도메인 매핑
  # 도구명이 도메인명과 부분문자열로 일치하지 않는 경우를 보완합니다.
  # (예: "search_web"은 "web_search"를 부분문자열로 포함하지 않음)
  @tool_to_domain %{
    "search_web" => :web_search,
    "firecrawl_search" => :web_search,
    "firecrawl_scrape" => :web_search,
    "calculate" => :calculator,
    "execute_code" => :code
  }

  # Worker 이름의 타입 부분 → 도메인 매핑
  # (예: "research_worker" → :web_search)
  @name_type_to_domain %{
    "research" => :web_search
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
      {:ok, %Agent{name: "knowledge_worker", ...}}
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
      domain_atoms = Enum.map(matching_domains, fn {domain, _} -> domain end)
      domain_names = Enum.map(domain_atoms, &Atom.to_string/1)

      tool_matches =
        Enum.count(enabled_tools, fn tool ->
          tool_matches_domain?(tool, domain_atoms, domain_names)
        end)

      if length(enabled_tools) > 0 do
        tool_matches / length(enabled_tools) * 100
      else
        0
      end
    end
  end

  # 도구가 매칭 도메인에 속하는지 판정합니다.
  # 1) 명시적 매핑(@tool_to_domain) 우선 — 프로덕션 도구명을 정확히 매칭
  # 2) 폴백으로 부분문자열 매칭 — 테스트 픽스처/구버전 도구명 호환
  defp tool_matches_domain?(tool, domain_atoms, domain_names) do
    case Map.get(@tool_to_domain, tool) do
      nil -> Enum.any?(domain_names, &String.contains?(tool, &1))
      domain -> domain in domain_atoms
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

    # Worker 타입 키워드가 일치하는지 확인 (예: "research" → :web_search 도메인)
    domain_atom =
      Map.get(@name_type_to_domain, worker_type) ||
        safe_to_existing_atom(worker_type)

    domain_keywords = Map.get(@domain_keywords, domain_atom, [])

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

  # 임의 문자열로 atom 생성을 피하기 위해 이미 존재하는 atom만 변환합니다.
  defp safe_to_existing_atom(string) do
    String.to_existing_atom(string)
  rescue
    ArgumentError -> nil
  end
end
