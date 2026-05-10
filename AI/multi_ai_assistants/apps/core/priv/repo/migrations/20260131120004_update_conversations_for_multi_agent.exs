defmodule Core.Repo.Migrations.UpdateConversationsForMultiAgent do
  use Ecto.Migration

  def change do
    alter table(:conversations) do
      add :supervisor_agent_id, references(:agents, type: :binary_id, on_delete: :nothing)
      add :context_summary, :text
    end

    create index(:conversations, [:supervisor_agent_id])
  end
end
