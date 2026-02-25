#!/usr/bin/env elixir

# ConfigLoader 테스트 스크립트

alias Core.Agent.ConfigLoader
alias Core.Contexts.Agents
alias Core.Repo

IO.puts("=== ConfigLoader 테스트 시작 ===\n")

# 1. 모든 설정 파일 로드
IO.puts("1. 설정 파일 로드 중...")

case ConfigLoader.load_all_configs() do
  {:ok, agents} ->
    IO.puts("✓ #{length(agents)}개의 에이전트 설정 로드 성공\n")

    Enum.each(agents, fn agent ->
      IO.puts("  - #{agent.name} (#{agent.type})")
    end)

  {:error, errors} ->
    IO.puts("✗ 설정 로드 실패:")
    IO.inspect(errors)
end

IO.puts("")

# 2. DB에서 에이전트 조회
IO.puts("2. DB에서 에이전트 조회...")

all_agents = Agents.list_agents()
IO.puts("  총 #{length(all_agents)}개 에이전트")

supervisors = Agents.list_supervisors()
IO.puts("  - Supervisor: #{length(supervisors)}개")

workers = Agents.list_workers()
IO.puts("  - Worker: #{length(workers)}개")

IO.puts("")

# 3. 개별 에이전트 상세 정보
IO.puts("3. 에이전트 상세 정보:")

Enum.each(all_agents, fn agent ->
  IO.puts("\n  [#{agent.name}]")
  IO.puts("    Type: #{agent.type}")
  IO.puts("    Model: #{agent.model}")
  IO.puts("    Temperature: #{agent.temperature}")
  IO.puts("    Enabled Tools: #{inspect(agent.enabled_tools)}")
  IO.puts("    Config: #{inspect(agent.config)}")
  IO.puts("    System Prompt (처음 100자): #{String.slice(agent.system_prompt || "", 0, 100)}...")
end)

IO.puts("\n=== 테스트 완료 ===")
