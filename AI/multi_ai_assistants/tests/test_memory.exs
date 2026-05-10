#!/usr/bin/env elixir

# Memory 시스템 테스트 스크립트

alias Core.Agent.MemoryManager
alias Core.Contexts.Agents

IO.puts("=== Memory 시스템 테스트 ===\n")

# 1. Supervisor 에이전트 가져오기
IO.puts("1. Supervisor 에이전트 조회...")

supervisor = Agents.get_active_supervisor()

if !supervisor do
  IO.puts("✗ Supervisor를 찾을 수 없습니다.")
  System.halt(1)
end

IO.puts("  ✓ Supervisor: #{supervisor.name} (#{supervisor.id})")
IO.puts("")

# 2. 메모리 저장
IO.puts("2. 메모리 저장 테스트...")

# Conversation Summary
{:ok, _} =
  MemoryManager.store(
    supervisor.id,
    :conversation_summary,
    "user_preferences",
    %{
      preferred_language: "Korean",
      coding_style: "functional",
      verbosity: "detailed"
    },
    relevance_score: 0.9
  )

IO.puts("  ✓ Conversation Summary 저장")

# Learned Pattern
{:ok, _} =
  MemoryManager.store(
    supervisor.id,
    :learned_pattern,
    "error_handling",
    %{
      pattern: "Always log errors before returning",
      examples: ["Logger.error before {:error, reason}"],
      frequency: 5
    },
    relevance_score: 0.8
  )

IO.puts("  ✓ Learned Pattern 저장")

# Project Context
{:ok, _} =
  MemoryManager.store(
    supervisor.id,
    :project_context,
    "architecture",
    %{
      type: "Elixir Umbrella Project",
      apps: ["core", "web"],
      database: "SQLite",
      style: "Phoenix LiveView"
    },
    relevance_score: 1.0
  )

IO.puts("  ✓ Project Context 저장")

# Performance Metric
{:ok, _} =
  MemoryManager.store(
    supervisor.id,
    :performance_metric,
    "task_20260131_001",
    %{
      worker_used: "calculator_worker",
      duration_ms: 1234,
      success: true,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    },
    relevance_score: 0.5
  )

IO.puts("  ✓ Performance Metric 저장")
IO.puts("")

# 3. 메모리 검색
IO.puts("3. 메모리 검색 테스트...")

patterns = MemoryManager.retrieve(supervisor.id, :learned_pattern)
IO.puts("  - Learned Patterns: #{length(patterns)}개")

contexts = MemoryManager.retrieve(supervisor.id, :project_context)
IO.puts("  - Project Contexts: #{length(contexts)}개")

metrics = MemoryManager.retrieve(supervisor.id, :performance_metric)
IO.puts("  - Performance Metrics: #{length(metrics)}개")

summaries = MemoryManager.retrieve(supervisor.id, :conversation_summary)
IO.puts("  - Conversation Summaries: #{length(summaries)}개")

IO.puts("")

# 4. Markdown 내보내기
IO.puts("4. Markdown 내보내기...")

case MemoryManager.export_to_markdown(supervisor.id) do
  {:ok, file_path} ->
    IO.puts("  ✓ Markdown 파일 생성: #{file_path}")

    # 파일 내용 확인
    content = File.read!(file_path)
    lines = String.split(content, "\n") |> Enum.take(10)

    IO.puts("\n  파일 내용 (처음 10줄):")
    Enum.each(lines, fn line ->
      IO.puts("    #{line}")
    end)

  {:error, reason} ->
    IO.puts("  ✗ Markdown 내보내기 실패: #{inspect(reason)}")
end

IO.puts("")

# 5. 메모리 삭제 후 가져오기 테스트
IO.puts("5. Markdown 가져오기 테스트...")

# 기존 메모리 일부 삭제
MemoryManager.delete(supervisor.id, :learned_pattern, "error_handling")
IO.puts("  - 메모리 1개 삭제")

# 삭제 확인
patterns_after = MemoryManager.retrieve(supervisor.id, :learned_pattern)
IO.puts("  - 삭제 후 Patterns: #{length(patterns_after)}개")

# Markdown에서 다시 가져오기
case MemoryManager.import_from_markdown(supervisor.id) do
  {:ok, imported} ->
    IO.puts("  ✓ Markdown에서 #{length(imported)}개 메모리 가져오기 성공")

    # 복원 확인
    patterns_restored = MemoryManager.retrieve(supervisor.id, :learned_pattern)
    IO.puts("  - 복원 후 Patterns: #{length(patterns_restored)}개")

  {:error, reason} ->
    IO.puts("  ✗ Markdown 가져오기 실패: #{inspect(reason)}")
end

IO.puts("\n=== 테스트 완료 ===")
