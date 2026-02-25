defmodule Core.Repo.Migrations.UpdateMessagesForMultiAgent do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :agent_id, references(:agents, type: :binary_id, on_delete: :nothing)
      add :agent_task_id, references(:agent_tasks, type: :binary_id, on_delete: :nothing)
    end

    create index(:messages, [:agent_id])
    create index(:messages, [:agent_task_id])
  end
end
