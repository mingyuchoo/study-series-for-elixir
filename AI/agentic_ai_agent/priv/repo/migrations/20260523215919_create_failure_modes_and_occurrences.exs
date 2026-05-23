defmodule AgenticAiAgent.Repo.Migrations.CreateFailureModesAndOccurrences do
  use Ecto.Migration

  def change do
    # ----- Catalog: failure mode definitions (authored as YAML, synced) -----

    create table(:failure_modes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :slug, :string, null: false
      add :name, :string, null: false
      add :failure_type, :string, null: false
      add :severity, :string, null: false, default: "medium"
      add :trigger_condition, :text
      add :example, :text
      add :expected_recovery, :text
      add :detection_method, :text
      add :related_test_cases, {:array, :string}, default: []
      add :metadata, :map

      timestamps(type: :utc_datetime)
    end

    create unique_index(:failure_modes, [:slug])
    create index(:failure_modes, [:severity])
    create index(:failure_modes, [:failure_type])

    # ----- Occurrences: actual failures detected at runtime -----

    create table(:failure_occurrences, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :failure_mode_id,
          references(:failure_modes, type: :binary_id, on_delete: :nilify_all)

      add :run_id, references(:runs, type: :binary_id, on_delete: :delete_all)
      add :step_id, references(:steps, type: :binary_id, on_delete: :nilify_all)

      add :reason, :text
      add :context, :map
      add :detected_by, :string, default: "auto"
      add :notes, :text

      timestamps(type: :utc_datetime)
    end

    create index(:failure_occurrences, [:failure_mode_id])
    create index(:failure_occurrences, [:run_id])
    create index(:failure_occurrences, [:inserted_at])
  end
end
