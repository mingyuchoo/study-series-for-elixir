defmodule Core.Repo.Migrations.CreateAgentRuns do
  use Ecto.Migration

  def change do
    create table(:agent_runs, primary_key: false) do
      add(:id, :binary_id, primary_key: true)

      add(:conversation_id, references(:conversations, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      add(:user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false)
      add(:user_request, :text, null: false)
      add(:status, :string, null: false, default: "running")
      add(:round, :integer, null: false, default: 0)
      add(:transcript, :map, null: false, default: %{})
      add(:final_answer, :text)
      add(:error, :text)
      timestamps(type: :utc_datetime)
    end

    create(index(:agent_runs, [:conversation_id, :status]))

    alter table(:messages) do
      add(:agent_run_id, references(:agent_runs, type: :binary_id, on_delete: :nilify_all))
    end

    create(unique_index(:messages, [:agent_run_id]))
  end
end
