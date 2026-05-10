defmodule Core.Agent.RoutingRules do
  @moduledoc """
  Agent task routing rule 조회와 기본 rule seed를 담당합니다.
  """

  import Ecto.Query

  alias Core.Repo
  alias Core.Schema.AgentRoutingRule

  @domain_keywords %{
    "calculator" => [
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
    "code" => [
      "코드",
      "프로그램",
      "함수",
      "실행",
      "디버그",
      "테스트",
      "리팩토링",
      "구현"
    ],
    "web_search" => [
      "검색",
      "찾아",
      "알려",
      "최신",
      "뉴스",
      "정보",
      "조사",
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

  @tool_domains [
    {"search_web", "web_search"},
    {"web_search", "web_search"},
    {"firecrawl_search", "web_search"},
    {"firecrawl_scrape", "web_search"},
    {"calculate", "calculator"},
    {"calculator", "calculator"},
    {"execute_code", "code"},
    {"code_executor", "code"}
  ]

  @name_domains [
    {"research", "web_search"}
  ]

  def list_active_rules do
    AgentRoutingRule
    |> where([r], r.enabled == true)
    |> Repo.all()
    |> build_rule_index()
  end

  def seed_defaults do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert_all(AgentRoutingRule, default_rule_attrs(now),
      on_conflict: :nothing,
      conflict_target: [:rule_type, :domain, :pattern]
    )
  end

  def build_rule_index(rules) do
    Enum.reduce(
      rules,
      %{domain_keywords: %{}, tool_to_domain: %{}, name_type_to_domain: %{}},
      &put_routing_rule/2
    )
  end

  defp default_rule_attrs(now) do
    domain_keyword_rows(now) ++ tool_domain_rows(now) ++ name_domain_rows(now)
  end

  defp domain_keyword_rows(now) do
    Enum.flat_map(@domain_keywords, fn {domain, keywords} ->
      Enum.map(keywords, &rule_row(:domain_keyword, domain, &1, now))
    end)
  end

  defp tool_domain_rows(now) do
    Enum.map(@tool_domains, fn {tool, domain} ->
      rule_row(:tool_domain, domain, tool, now)
    end)
  end

  defp name_domain_rows(now) do
    Enum.map(@name_domains, fn {name_type, domain} ->
      rule_row(:name_domain, domain, name_type, now)
    end)
  end

  defp rule_row(rule_type, domain, pattern, now) do
    %{
      id: Ecto.UUID.generate(),
      rule_type: rule_type,
      domain: domain,
      pattern: pattern,
      enabled: true,
      inserted_at: now,
      updated_at: now
    }
  end

  defp put_routing_rule(%AgentRoutingRule{rule_type: :domain_keyword} = rule, acc) do
    update_in(acc.domain_keywords, fn keywords_by_domain ->
      Map.update(keywords_by_domain, rule.domain, [rule.pattern], &[rule.pattern | &1])
    end)
  end

  defp put_routing_rule(%AgentRoutingRule{rule_type: :tool_domain} = rule, acc) do
    put_in(acc.tool_to_domain[rule.pattern], rule.domain)
  end

  defp put_routing_rule(%AgentRoutingRule{rule_type: :name_domain} = rule, acc) do
    put_in(acc.name_type_to_domain[rule.pattern], rule.domain)
  end
end
