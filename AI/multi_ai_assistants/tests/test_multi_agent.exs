#!/usr/bin/env elixir

# Multi-Agent 시스템 통합 테스트 스크립트

alias Core.Repo
alias Core.Schema.{Conversation, Agent}
alias Core.Contexts.Agents
alias Core.Agent.{Supervisor, SupervisorAgent}

IO.puts("=== Multi-Agent 시스템 통합 테스트 ===\n")

# 1. 에이전트 설정 확인
IO.puts("1. 에이전트 설정 확인...")

supervisors = Agents.list_supervisors()
workers = Agents.list_workers()

IO.puts("  - Supervisor: #{length(supervisors)}개")
Enum.each(supervisors, fn agent ->
  IO.puts("    * #{agent.name} (#{agent.display_name})")
end)

IO.puts("  - Worker: #{length(workers)}개")
Enum.each(workers, fn agent ->
  IO.puts("    * #{agent.name} (#{agent.display_name})")
end)

if supervisors == [] or workers == [] do
  IO.puts("\n✗ 에이전트가 없습니다. 먼저 ConfigLoader를 실행하세요:")
  IO.puts("  mix run tests/test_config_loader.exs")
  System.halt(1)
end

IO.puts("")

# 2. 대화 생성
IO.puts("2. 테스트 대화 생성...")

supervisor = hd(supervisors)

{:ok, conversation} =
  %Conversation{}
  |> Conversation.changeset(%{
    title: "Multi-Agent Test",
    supervisor_agent_id: supervisor.id
  })
  |> Repo.insert()

IO.puts("  ✓ 대화 생성: #{conversation.id}")
IO.puts("  ✓ Supervisor: #{supervisor.name}")
IO.puts("")

# 3. SupervisorAgent 시작
IO.puts("3. SupervisorAgent 시작...")

case Supervisor.start_supervisor_agent(supervisor.id, conversation.id) do
  {:ok, pid} ->
    IO.puts("  ✓ SupervisorAgent 시작 성공: #{inspect(pid)}")

  {:error, {:already_started, pid}} ->
    IO.puts("  ✓ SupervisorAgent 이미 실행 중: #{inspect(pid)}")

  {:error, reason} ->
    IO.puts("  ✗ SupervisorAgent 시작 실패: #{inspect(reason)}")
    System.halt(1)
end

IO.puts("")

# 4. 계산 요청 테스트
IO.puts("4. 계산 요청 테스트...")

test_request = "2 + 2를 계산해줘"
IO.puts("  요청: #{test_request}")

case SupervisorAgent.chat(conversation.id, test_request) do
  {:ok, response} ->
    IO.puts("  ✓ 응답: #{response}")

  {:error, reason} ->
    IO.puts("  ✗ 오류: #{inspect(reason)}")
end

IO.puts("")

# 5. 일반 요청 테스트
IO.puts("5. 일반 요청 테스트...")

test_request = "안녕하세요"
IO.puts("  요청: #{test_request}")

case SupervisorAgent.chat(conversation.id, test_request) do
  {:ok, response} ->
    IO.puts("  ✓ 응답: #{response}")

  {:error, reason} ->
    IO.puts("  ✗ 오류: #{inspect(reason)}")
end

IO.puts("")

# 6. 작업 기록 확인
IO.puts("6. 작업 기록 확인...")

tasks = Core.Agent.Coordinator.list_tasks(conversation.id)
IO.puts("  총 #{length(tasks)}개 작업")

Enum.each(tasks, fn task ->
  IO.puts("  - #{task.task_type}: #{task.status}")
  IO.puts("    Input: #{inspect(task.input)}")

  if task.result do
    IO.puts("    Result: #{inspect(task.result)}")
  end
end)

IO.puts("")

# 7. 에이전트 간 상호작용 확인
IO.puts("7. 에이전트 간 상호작용 확인...")

interactions = Core.Agent.Coordinator.list_interactions(conversation.id)
IO.puts("  총 #{length(interactions)}개 상호작용")

Enum.each(interactions, fn interaction ->
  IO.puts("  - #{interaction.interaction_type}")
  IO.puts("    Data: #{inspect(interaction.data)}")
end)

IO.puts("\n=== 테스트 완료 ===")
