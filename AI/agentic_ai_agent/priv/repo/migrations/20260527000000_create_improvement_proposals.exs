defmodule AgenticAiAgent.Repo.Migrations.CreateImprovementProposals do
  use Ecto.Migration

  def change do
    create table(:improvement_proposals, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # What kind of artifact to change. Currently only "card_edit" is wired
      # in the Improver; others are reserved for future passes.
      add :kind, :string, null: false, default: "card_edit"
      add :target, :string, null: false

      # The full proposed body (e.g. complete new YAML). Null for kinds that
      # don't fit a single body (reserved).
      add :proposed_body, :text

      # Free-form structured payload for non-body kinds (future use).
      add :proposed_change, :map

      add :justification, :text
      add :expected_score_delta, :float
      add :supporting_run_ids, {:array, :string}, default: []

      add :status, :string, null: false, default: "pending"
      add :decided_by, :string
      add :decided_at, :utc_datetime
      add :decision_reason, :string
      add :applied_at, :utc_datetime
      add :apply_error, :text

      # When the proposer LLM returns garbage, we still persist the raw
      # output here so an operator can inspect what went wrong.
      add :raw_response, :text

      timestamps(type: :utc_datetime)
    end

    create index(:improvement_proposals, [:status, :inserted_at])
    create index(:improvement_proposals, [:target])
  end
end
