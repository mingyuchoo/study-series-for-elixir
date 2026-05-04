defmodule Core.Repo.Migrations.CreateAgentRoutingRules do
  use Ecto.Migration

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

  def change do
    create table(:agent_routing_rules, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:rule_type, :string, null: false)
      add(:domain, :string, null: false)
      add(:pattern, :string, null: false)
      add(:enabled, :boolean, default: true)

      timestamps(type: :utc_datetime)
    end

    create(unique_index(:agent_routing_rules, [:rule_type, :domain, :pattern]))
    create(index(:agent_routing_rules, [:rule_type, :enabled]))

    execute(&seed_rules/0, &delete_rules/0)
  end

  defp seed_rules do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    rows =
      domain_keyword_rows(now) ++
        tool_domain_rows(now) ++
        name_domain_rows(now)

    repo().insert_all("agent_routing_rules", rows,
      on_conflict: :nothing,
      conflict_target: [:rule_type, :domain, :pattern]
    )
  end

  defp delete_rules do
    execute("DELETE FROM agent_routing_rules")
  end

  defp domain_keyword_rows(now) do
    Enum.flat_map(@domain_keywords, fn {domain, keywords} ->
      Enum.map(keywords, fn keyword ->
        rule_row(:domain_keyword, domain, keyword, now)
      end)
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
      rule_type: Atom.to_string(rule_type),
      domain: domain,
      pattern: pattern,
      enabled: 1,
      inserted_at: now,
      updated_at: now
    }
  end
end
