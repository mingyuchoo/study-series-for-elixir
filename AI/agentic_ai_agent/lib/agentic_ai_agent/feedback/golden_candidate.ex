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
  @polarities ~w(negative positive)

  schema "golden_candidates" do
    belongs_to :run, Run

    field :user_input, :string
    field :assistant_answer, :string
    field :corrected_answer, :string
    field :user_note, :string
    field :target_card_slug, :string

    field :status, :string, default: "pending"

    # "negative" — answer was wrong, needs corrected_answer at promotion.
    # "positive" — answer was great, assistant_answer IS the gold and is
    # promoted to wins.jsonl (no corrected_answer required).
    field :polarity, :string, default: "negative"

    field :promoted_to_path, :string
    field :promoted_at, :utc_datetime
    field :promoted_by, :string
    field :dismissed_reason, :string
    field :flagged_by, :string

    # Quality estimate (0.0–1.0) from the LLM-as-judge auto-flagger.
    # Used for both polarities: low score → auto-flag (negative), high
    # score → auto-praise (positive). Nil when human-flagged.
    field :judge_score, :float

    timestamps(type: :utc_datetime)
  end

  def polarities, do: @polarities

  @castable ~w(run_id user_input assistant_answer corrected_answer user_note
               target_card_slug status polarity promoted_to_path promoted_at
               promoted_by dismissed_reason flagged_by judge_score)a

  def changeset(candidate, attrs) do
    candidate
    |> cast(attrs, @castable)
    |> validate_required([:user_input, :status])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:polarity, @polarities)
  end
end
