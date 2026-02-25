defmodule Core.Repo.Migrations.CreateAgentMemoriesTable do
  use Ecto.Migration

  def change do
    create table(:agent_memories, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :agent_id, references(:agents, type: :binary_id, on_delete: :delete_all), null: false
      add :conversation_id, references(:conversations, type: :binary_id, on_delete: :delete_all)
      add :memory_type, :string, null: false
      add :key, :string, null: false
      add :value, :text
      add :metadata, :text
      add :relevance_score, :float
      add :expires_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:agent_memories, [:agent_id])
    create index(:agent_memories, [:conversation_id])
    create index(:agent_memories, [:memory_type])
    create index(:agent_memories, [:agent_id, :memory_type])
    create index(:agent_memories, [:agent_id, :key])
  end
end
