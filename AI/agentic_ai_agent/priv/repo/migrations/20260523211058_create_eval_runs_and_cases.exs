defmodule AgenticAiAgent.Repo.Migrations.CreateEvalRunsAndCases do
  use Ecto.Migration

  def change do
    create table(:eval_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :agentic_card_id, references(:agentic_cards, type: :binary_id, on_delete: :nilify_all)
      add :golden_path, :string
      add :rubric, :map
      add :pass_threshold, :float
      add :started_at, :utc_datetime_usec
      add :finished_at, :utc_datetime_usec
      add :total_cases, :integer, default: 0
      add :passed_cases, :integer, default: 0
      add :average_score, :float
      add :status, :string, default: "running"
      add :summary, :map

      timestamps(type: :utc_datetime)
    end

    create index(:eval_runs, [:agentic_card_id])
    create index(:eval_runs, [:inserted_at])

    create table(:eval_cases, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :eval_run_id, references(:eval_runs, type: :binary_id, on_delete: :delete_all), null: false
      add :run_id, references(:runs, type: :binary_id, on_delete: :nilify_all)
      add :case_id, :string, null: false
      add :task_type, :string
      add :input, :text
      add :expected, :map
      add :expected_tools, {:array, :string}, default: []
      add :final_answer, :text
      add :scores, :map
      add :total_score, :float
      add :passed, :boolean, default: false
      add :notes, :text

      timestamps(type: :utc_datetime)
    end

    create index(:eval_cases, [:eval_run_id])
    create index(:eval_cases, [:case_id])
  end
end
