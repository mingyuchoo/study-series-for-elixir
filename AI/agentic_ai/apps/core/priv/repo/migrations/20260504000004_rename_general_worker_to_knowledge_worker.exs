defmodule Core.Repo.Migrations.RenameGeneralWorkerToKnowledgeWorker do
  use Ecto.Migration

  def up do
    old_name = "general" <> "_worker"
    new_name = "knowledge_worker"
    new_display_name = "Knowledge Worker"
    new_description = "LLM 자체 지식과 Vector RAG 지식 기반의 텍스트 생성/요약/번역 등 외부 호출이 필요 없는 작업을 수행하는 Worker"
    new_markdown_path = "config/agents/worker_knowledge.md"

    execute("""
    UPDATE agents
    SET name = '#{new_name}',
        display_name = '#{new_display_name}',
        description = '#{new_description}',
        markdown_path = '#{new_markdown_path}'
    WHERE name = '#{old_name}'
      AND NOT EXISTS (SELECT 1 FROM agents WHERE name = '#{new_name}')
    """)
  end

  def down do
    old_name = "general" <> "_worker"
    new_name = "knowledge_worker"
    old_display_name = "General" <> " Worker"
    old_description = "LLM 자체 지식 기반의 텍스트 생성/요약/번역 등 외부 호출이 필요 없는 작업을 수행하는 Worker"
    old_markdown_path = "config/agents/worker_" <> "general.md"

    execute("""
    UPDATE agents
    SET name = '#{old_name}',
        display_name = '#{old_display_name}',
        description = '#{old_description}',
        markdown_path = '#{old_markdown_path}'
    WHERE name = '#{new_name}'
      AND NOT EXISTS (SELECT 1 FROM agents WHERE name = '#{old_name}')
    """)
  end
end
