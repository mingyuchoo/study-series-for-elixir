defmodule AgentDomain.RoutingRules do
  @moduledoc "Pure routing rule defaults and index construction."

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

  def default_rules do
    domain_keywords =
      Enum.flat_map(@domain_keywords, fn {domain, keywords} ->
        Enum.map(keywords, &%{rule_type: :domain_keyword, domain: domain, pattern: &1})
      end)

    tool_domains =
      Enum.map(@tool_domains, fn {tool, domain} ->
        %{rule_type: :tool_domain, domain: domain, pattern: tool}
      end)

    name_domains =
      Enum.map(@name_domains, fn {name, domain} ->
        %{rule_type: :name_domain, domain: domain, pattern: name}
      end)

    domain_keywords ++ tool_domains ++ name_domains
  end

  def build_rule_index(rules) do
    Enum.reduce(
      rules,
      %{domain_keywords: %{}, tool_to_domain: %{}, name_type_to_domain: %{}},
      &put_routing_rule/2
    )
  end

  defp put_routing_rule(%{rule_type: :domain_keyword} = rule, acc) do
    update_in(acc.domain_keywords, fn keywords_by_domain ->
      Map.update(keywords_by_domain, rule.domain, [rule.pattern], &[rule.pattern | &1])
    end)
  end

  defp put_routing_rule(%{rule_type: :tool_domain} = rule, acc) do
    put_in(acc.tool_to_domain[rule.pattern], rule.domain)
  end

  defp put_routing_rule(%{rule_type: :name_domain} = rule, acc) do
    put_in(acc.name_type_to_domain[rule.pattern], rule.domain)
  end
end
