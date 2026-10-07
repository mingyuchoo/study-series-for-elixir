defmodule Core.Repo.Migrations.ScopeAgentMemories do
  use Ecto.Migration

  def change do
    alter table(:agent_memories) do
      add(:user_id, references(:users, type: :binary_id, on_delete: :delete_all))
    end

    create(index(:agent_memories, [:user_id, :agent_id, :memory_type]))
  end
end
