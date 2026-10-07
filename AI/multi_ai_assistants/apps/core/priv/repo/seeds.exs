alias Core.Repo
alias Core.Agent.RoutingRules
alias Core.Contexts.Accounts
alias Core.Contexts.Mcps
alias Core.Agent.ConfigLoader
alias Core.Schema.{Tool, User}

# ------------------------------------------------------------------
# 1) 초기 관리자 계정 생성 (ADMIN_EMAIL / ADMIN_PASSWORD 환경변수 사용)
# ------------------------------------------------------------------
admin_email = System.get_env("ADMIN_EMAIL") || "admin@example.com"
admin_password = System.get_env("ADMIN_PASSWORD") || "Admin123!"

case Repo.get_by(User, email: String.downcase(admin_email)) do
  nil ->
    case Accounts.register_user(%{email: admin_email, password: admin_password}) do
      {:ok, user} ->
        IO.puts("✓ 관리자 계정 생성: #{user.email}")

      {:error, changeset} ->
        IO.puts("✗ 관리자 계정 생성 실패:")

        Enum.each(changeset.errors, fn {field, {msg, _}} ->
          IO.puts("    - #{field}: #{msg}")
        end)
    end

  _user ->
    IO.puts("· 관리자 계정 존재: #{admin_email}")
end

# ------------------------------------------------------------------
# 2) 기본 에이전트 (config/agents/*.md → DB)
# ------------------------------------------------------------------
agents_dir =
  [
    Path.expand("../../../../../config/agents", __DIR__),
    Path.expand("../../../../config/agents", __DIR__),
    "config/agents"
  ]
  |> Enum.find(&File.dir?/1)

if agents_dir do
  case ConfigLoader.load_all_configs(agents_dir) do
    {:ok, agents} ->
      IO.puts("✓ 에이전트 #{length(agents)}개 시드 (#{agents_dir})")

    {:error, errors} ->
      IO.puts("⚠ 에이전트 시드 중 일부 실패: #{inspect(errors)}")
  end
else
  IO.puts("· 에이전트 시드 디렉토리를 찾지 못해 건너뜁니다.")
end

# ------------------------------------------------------------------
# 3) 기본 도구 레지스트리 (실행 모듈/정의 → DB, 이름 기준 upsert)
# ------------------------------------------------------------------
tools = [
  {"get_current_time", Core.Agent.Tools.DateTime},
  {"search_web", Core.Agent.Tools.WebSearch},
  {"calculate", Core.Agent.Tools.Calculator},
  {"read_file", Core.Agent.Tools.FileSystem},
  {"write_file", Core.Agent.Tools.FileSystem},
  {"list_directory", Core.Agent.Tools.FileSystem},
  {"search_vector_rag", Core.Agent.Tools.VectorRagSearch},
  {"execute_code", Core.Agent.Tools.CodeExecutor},
  {"mcp_filesystem_call", Core.Agent.Tools.Mcp},
  {"mcp_desktop_commander_call", Core.Agent.Tools.Mcp},
  {"firecrawl_scrape", Core.Agent.Tools.Firecrawl},
  {"firecrawl_search", Core.Agent.Tools.Firecrawl}
]

Enum.each(tools, fn {name, module} ->
  definition = module.definition(name) || %{description: nil, parameters: nil}

  attrs = %{
    name: name,
    description: definition[:description] || definition["description"],
    parameters: definition[:parameters] || definition["parameters"],
    module_name: Atom.to_string(module),
    enabled: true
  }

  case Repo.get_by(Tool, name: name) do
    nil ->
      case %Tool{} |> Tool.changeset(attrs) |> Repo.insert() do
        {:ok, _} -> IO.puts("✓ 도구 시드: #{name}")
        {:error, cs} -> IO.puts("✗ 도구 시드 실패 #{name}: #{inspect(cs.errors)}")
      end

    tool ->
      case tool |> Tool.changeset(attrs) |> Repo.update() do
        {:ok, _} -> IO.puts("· 도구 갱신: #{name}")
        {:error, cs} -> IO.puts("✗ 도구 갱신 실패 #{name}: #{inspect(cs.errors)}")
      end
  end
end)

# ------------------------------------------------------------------
# 4) 기본 라우팅 규칙
# ------------------------------------------------------------------
{inserted_count, _} = RoutingRules.seed_defaults()
IO.puts("✓ 라우팅 규칙 시드: #{inserted_count}개")

# ------------------------------------------------------------------
# 5) 기본 MCP 서버 (.mcp.json → DB, 이름 기준 upsert)
# ------------------------------------------------------------------
mcp_json_path =
  [
    Path.expand("../../../../../.mcp.json", __DIR__),
    Path.expand("../../../../.mcp.json", __DIR__),
    ".mcp.json"
  ]
  |> Enum.find(&File.exists?/1)

if mcp_json_path do
  with {:ok, content} <- File.read(mcp_json_path),
       {:ok, %{"mcpServers" => servers}} <- Jason.decode(content) do
    Enum.each(servers, fn {name, cfg} ->
      attrs = %{
        name: name,
        command: cfg["command"] || "",
        args: cfg["args"] || [],
        env: cfg["env"] || %{},
        enabled: Map.get(cfg, "enabled", true),
        local_permission_level: cfg["local_permission_level"] || "none"
      }

      case Mcps.get_mcp_by_name(name) do
        nil ->
          case Mcps.create_mcp(attrs) do
            {:ok, _} -> IO.puts("✓ MCP 시드: #{name}")
            {:error, cs} -> IO.puts("✗ MCP 시드 실패 #{name}: #{inspect(cs.errors)}")
          end

        existing ->
          IO.puts("· MCP 존재: #{name} (건너뜀)")
          _ = existing
      end
    end)
  else
    _ -> IO.puts("⚠ .mcp.json 파싱 실패")
  end
else
  IO.puts("· .mcp.json을 찾지 못해 MCP 시드를 건너뜁니다.")
end

IO.puts("\n=== 시드 완료 ===")
