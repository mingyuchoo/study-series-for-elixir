defmodule AgentDomain.TaskRouter do
  @moduledoc """
  사용자 요청을 분석하여 적절한 Worker를 선택합니다.

  키워드 기반 매칭과 Worker의 능력(description, enabled_tools)을
  분석하여 가장 적합한 Worker를 반환합니다.
  """


  @doc "Selects and scores a worker using supplied routing rules. No storage or logging occurs here."
  def select_worker(_user_request, [], _rules), do: {:error, :no_workers_available}

  def select_worker(user_request, workers, rules) do
    case select_worker_with_score(user_request, workers, rules) do
      {:ok, worker, _score} -> {:ok, worker}
      error -> error
    end
  end

  def select_worker_with_score(_user_request, [], _rules),
    do: {:error, :no_workers_available}

  def select_worker_with_score(user_request, workers, rules) do
    workers
    |> Enum.map(fn worker -> {worker, calculate_match_score(user_request, worker, rules)} end)
    |> Enum.sort_by(fn {_worker, score} -> score end, :desc)
    |> case do
      [{worker, score} | _] -> {:ok, worker, score}
      [] -> {:error, :no_workers_available}
    end
  end

  # 비공개 함수들

  defp calculate_match_score(user_request, worker, rules) do
    description_score = calculate_description_score(user_request, worker.description)
    tools_score = calculate_tools_score(user_request, worker.enabled_tools, rules)
    name_score = calculate_name_score(user_request, worker.name, rules)

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

      score_ratio(matches, keywords)
    end)
  end

  defp calculate_tools_score(user_request, enabled_tools, rules) do
    request_lower = String.downcase(user_request)

    # 요청이 도메인 키워드와 일치하는지 확인
    matching_domains =
      Enum.filter(rules.domain_keywords, fn {_domain, keywords} ->
        Enum.any?(keywords, &String.contains?(request_lower, &1))
      end)

    if Enum.empty?(matching_domains) do
      0
    else
      domain_atoms = Enum.map(matching_domains, fn {domain, _} -> domain end)

      tool_matches =
        Enum.count(enabled_tools, fn tool ->
          tool_matches_domain?(tool, domain_atoms, rules.tool_to_domain)
        end)

      score_ratio(tool_matches, enabled_tools)
    end
  end

  # 도구가 매칭 도메인에 속하는지 판정합니다.
  # 1) DB 명시 매핑 우선 — 프로덕션 도구명을 정확히 매칭
  # 2) 폴백으로 부분문자열 매칭 — 테스트 픽스처/구버전 도구명 호환
  defp tool_matches_domain?(tool, domains, tool_to_domain) do
    case Map.get(tool_to_domain, tool) do
      nil -> Enum.any?(domains, &String.contains?(tool, &1))
      domain -> domain in domains
    end
  end

  defp calculate_name_score(user_request, name, rules) do
    request_lower = String.downcase(user_request)
    name_lower = String.downcase(name)

    # 이름에서 Worker 타입 추출 (예: "calculator_worker"에서 "calculator")
    worker_type =
      name_lower
      |> String.replace("_worker", "")
      |> String.replace("_agent", "")

    # Worker 타입 키워드가 일치하는지 확인 (예: "research" → "web_search" 도메인)
    domain = Map.get(rules.name_type_to_domain, worker_type, worker_type)

    domain_keywords = Map.get(rules.domain_keywords, domain, [])

    matches = Enum.count(domain_keywords, &String.contains?(request_lower, &1))

    score_ratio(matches, domain_keywords)
  end

  defp score_ratio(_matches, []), do: 0
  defp score_ratio(matches, values), do: matches / length(values) * 100

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
