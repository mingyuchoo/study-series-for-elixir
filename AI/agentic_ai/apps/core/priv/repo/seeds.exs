alias Core.Repo
alias Core.Contexts.Accounts
alias Core.Contexts.Mcps
alias Core.Agent.ConfigLoader
alias Core.Schema.User

require Logger

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
# 3) 기본 MCP 서버 (.mcp.json → DB, 이름 기준 upsert)
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
        enabled: true
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
