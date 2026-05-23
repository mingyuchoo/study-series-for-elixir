defmodule AgenticAiAgent.Repo.Migrations.AddSubagentAndApprovals do
  use Ecto.Migration

  def change do
    alter table(:runs) do
      add :parent_run_id, references(:runs, type: :binary_id, on_delete: :nilify_all)
      add :skill_slug, :string
    end

    create index(:runs, [:parent_run_id])

    create table(:approvals, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :run_id, references(:runs, type: :binary_id, on_delete: :delete_all), null: false
      add :step_id, references(:steps, type: :binary_id, on_delete: :nilify_all)
      add :tool_call_id, :string, null: false
      add :tool_name, :string, null: false
      add :input, :map
      add :risk_level, :string, null: false
      # pending | approved | denied | revised
      add :status, :string, default: "pending", null: false
      add :revised_input, :map
      add :decided_at, :utc_datetime
      add :decided_by, :string
      add :notes, :text

      timestamps(type: :utc_datetime)
    end

    create index(:approvals, [:run_id])
    create index(:approvals, [:status])
  end
end
