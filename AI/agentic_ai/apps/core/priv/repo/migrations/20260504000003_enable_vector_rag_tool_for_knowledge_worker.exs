defmodule Core.Repo.Migrations.EnableVectorRagToolForKnowledgeWorker do
  use Ecto.Migration

  def up do
    worker_name = "knowledge_worker"

    execute("""
    UPDATE agents
    SET enabled_tools = '["read_file","write_file","execute_code","search_vector_rag"]'
    WHERE name = '#{worker_name}'
      AND (enabled_tools IS NULL OR enabled_tools NOT LIKE '%search_vector_rag%')
    """)
  end

  def down do
    worker_name = "knowledge_worker"

    execute("""
    UPDATE agents
    SET enabled_tools = '["read_file","write_file","execute_code"]'
    WHERE name = '#{worker_name}'
      AND enabled_tools LIKE '%search_vector_rag%'
    """)
  end
end
