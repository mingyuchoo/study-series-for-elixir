defmodule AgenticAiAgent.Improver.Proposal do
  @moduledoc """
  A persisted improvement suggestion produced by `AgenticAiAgent.Improver`.

  Lifecycle:

      pending  → (operator) → approved → (apply!) → applied
                             ↘
                              rejected
      pending  → (parse fail) → malformed   (kept for audit, never applied)
      approved → (apply error) → failed     (apply attempted, surfaced error)
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @kinds ~w(card_edit skill_add tool_policy_change golden_case_add noop)
  @statuses ~w(pending approved staging staged_passed staged_failed rejected applied failed malformed)

  schema "improvement_proposals" do
    field :kind, :string, default: "card_edit"
    field :target, :string
    field :proposed_body, :string
    field :proposed_change, :map
    field :justification, :string
    field :expected_score_delta, :float
    field :supporting_run_ids, {:array, :string}, default: []

    field :status, :string, default: "pending"
    field :decided_by, :string
    field :decided_at, :utc_datetime
    field :decision_reason, :string
    field :applied_at, :utc_datetime
    field :apply_error, :string
    field :raw_response, :string

    # Phase 4 — Staging + auto-validation
    field :staging_slug, :string
    field :staging_eval_run_id, :string
    field :baseline_eval_run_id, :string
    field :baseline_score, :float
    field :staging_score, :float
    field :score_delta, :float

    # Phase 6 — Autonomous cycle
    field :auto_promoted, :boolean, default: false
    field :rolled_back_at, :utc_datetime
    field :rolled_back_reason, :string

    timestamps(type: :utc_datetime)
  end

  @castable ~w(kind target proposed_body proposed_change justification
               expected_score_delta supporting_run_ids status decided_by
               decided_at decision_reason applied_at apply_error
               raw_response staging_slug staging_eval_run_id
               baseline_eval_run_id baseline_score staging_score
               score_delta auto_promoted rolled_back_at rolled_back_reason)a

  def changeset(proposal, attrs) do
    proposal
    |> cast(attrs, @castable)
    |> validate_required([:kind, :target, :status])
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:status, @statuses)
  end
end
