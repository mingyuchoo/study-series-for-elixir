defmodule AgenticAiAgent.Repo.Migrations.CreateDesignAndTraceTables do
  use Ecto.Migration

  def change do
    # ----- Design layer -----

    create table(:agentic_cards, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :slug, :string, null: false
      add :name, :string, null: false
      add :role, :text
      add :goal, :text
      add :scope, :text
      add :capabilities, :map
      add :tool_policy, :map
      add :reasoning_policy, :map
      add :safety_policy, :map
      add :output_contract, :map
      add :evaluation_mapping, :map
      add :metadata, :map

      timestamps(type: :utc_datetime)
    end

    create unique_index(:agentic_cards, [:slug])

    create table(:task_taxonomies, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :agentic_card_id, references(:agentic_cards, type: :binary_id, on_delete: :delete_all)
      add :task_type, :string, null: false
      add :domain, :string
      add :complexity, :string
      add :risk_level, :string
      add :required_tools, {:array, :string}, default: []
      add :success_criteria, :text

      timestamps(type: :utc_datetime)
    end

    create index(:task_taxonomies, [:agentic_card_id])
    create index(:task_taxonomies, [:task_type])

    create table(:capability_matrices, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :agentic_card_id, references(:agentic_cards, type: :binary_id, on_delete: :delete_all)
      add :supported_capabilities, {:array, :string}, default: []
      add :supported_inputs, {:array, :string}, default: []
      add :supported_outputs, {:array, :string}, default: []
      add :required_tools, {:array, :string}, default: []
      add :constraints, :text
      add :known_limitations, :text

      timestamps(type: :utc_datetime)
    end

    create index(:capability_matrices, [:agentic_card_id])

    create table(:workflow_graphs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :agentic_card_id, references(:agentic_cards, type: :binary_id, on_delete: :delete_all)
      add :name, :string, null: false
      add :states, :map
      add :transitions, :map
      add :terminal_states, {:array, :string}, default: []
      add :approval_points, {:array, :string}, default: []

      timestamps(type: :utc_datetime)
    end

    create index(:workflow_graphs, [:agentic_card_id])

    # ----- Tool Registry (persistent contract) -----

    create table(:tool_specs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :purpose, :text
      add :input_schema, :map
      add :output_schema, :map
      add :preconditions, :text
      add :side_effects, :text
      add :failure_modes, {:array, :string}, default: []
      add :retry_policy, :map
      add :risk_level, :string, default: "low"
      add :enabled, :boolean, default: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tool_specs, [:name])

    # ----- Trace / Observation layer -----

    create table(:runs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :agentic_card_id, references(:agentic_cards, type: :binary_id, on_delete: :nilify_all)
      add :user_input, :text
      add :status, :string, default: "pending"
      add :final_answer, :text
      add :errors, :map
      add :started_at, :utc_datetime_usec
      add :finished_at, :utc_datetime_usec
      add :latency_ms, :integer
      add :cost_cents, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:runs, [:agentic_card_id])
    create index(:runs, [:status])
    create index(:runs, [:inserted_at])

    create table(:steps, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :run_id, references(:runs, type: :binary_id, on_delete: :delete_all), null: false
      add :idx, :integer, null: false
      add :kind, :string, null: false
      add :payload, :map
      add :latency_ms, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:steps, [:run_id])
    create unique_index(:steps, [:run_id, :idx])

    create table(:tool_calls, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :run_id, references(:runs, type: :binary_id, on_delete: :delete_all), null: false
      add :step_id, references(:steps, type: :binary_id, on_delete: :delete_all)
      add :tool_name, :string, null: false
      add :input, :map
      add :output, :map
      add :error, :text
      add :latency_ms, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:tool_calls, [:run_id])
    create index(:tool_calls, [:tool_name])
  end
end
