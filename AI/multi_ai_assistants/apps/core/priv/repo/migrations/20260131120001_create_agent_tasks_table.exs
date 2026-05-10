defmodule Core.Repo.Migrations.CreateAgentTasksTable do
  use Ecto.Migration

  def change do
    create table(:agent_tasks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :conversation_id, references(:conversations, type: :binary_id, on_delete: :delete_all),
          null: false
      add :supervisor_id, references(:agents, type: :binary_id, on_delete: :nothing),
          null: false
      add :worker_id, references(:agents, type: :binary_id, on_delete: :nothing)
      add :task_type, :string
      add :description, :text
      add :input_data, :text
      add :output_data, :text
      add :status, :string, default: "pending"
      add :priority, :integer, default: 0
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime
      add :error_message, :text

      timestamps(type: :utc_datetime)
    end

    create index(:agent_tasks, [:conversation_id])
    create index(:agent_tasks, [:supervisor_id])
    create index(:agent_tasks, [:worker_id])
    create index(:agent_tasks, [:status])
  end
end
