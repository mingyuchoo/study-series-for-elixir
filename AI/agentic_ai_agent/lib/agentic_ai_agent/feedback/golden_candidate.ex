defmodule AgenticAiAgent.Feedback.GoldenCandidate do
  @moduledoc """
  A chat run that the user flagged as "wrong", awaiting curation into the
  golden regression dataset.

  Lifecycle:

      pending   → (operator fills corrected_answer + Promote) → promoted
      pending   → (operator dismisses)                        → dismissed
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias AgenticAiAgent.Traces.Run

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(pending promoted dismissed)

  schema "golden_candidates" do
    belongs_to :run, Run

    field :user_input, :string
    field :assistant_answer, :string
    field :corrected_answer, :string
    field :user_note, :string
    field :target_card_slug, :string

    field :status, :string, default: "pending"

    field :promoted_to_path, :string
    field :promoted_at, :utc_datetime
    field :promoted_by, :string
    field :dismissed_reason, :string
    field :flagged_by, :string

    # Quality estimate (0.0–1.0) from the LLM-as-judge auto-flagger. Nil
    # when the candidate was created by a human 👎.
    field :judge_score, :float

    timestamps(type: :utc_datetime)
  end

  @castable ~w(run_id user_input assistant_answer corrected_answer user_note
               target_card_slug status promoted_to_path promoted_at
               promoted_by dismissed_reason flagged_by judge_score)a

  def changeset(candidate, attrs) do
    candidate
    |> cast(attrs, @castable)
    |> validate_required([:user_input, :status])
    |> validate_inclusion(:status, @statuses)
  end
end
