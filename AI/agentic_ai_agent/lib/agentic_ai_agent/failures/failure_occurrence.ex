defmodule AgenticAiAgent.Failures.FailureOccurrence do
  @moduledoc """
  A single observed failure: links a run (and optionally a step) to a
  catalog entry. `failure_mode_id` is nullable for occurrences that the
  detector couldn't classify — the row is still useful as raw evidence.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias AgenticAiAgent.Failures.FailureMode
  alias AgenticAiAgent.Traces.{Run, Step}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "failure_occurrences" do
    belongs_to :failure_mode, FailureMode
    belongs_to :run, Run
    belongs_to :step, Step

    field :reason, :string
    field :context, :map
    field :detected_by, :string, default: "auto"
    field :notes, :string

    timestamps(type: :utc_datetime)
  end

  @castable ~w(failure_mode_id run_id step_id reason context detected_by notes)a

  def changeset(occ, attrs) do
    occ
    |> cast(attrs, @castable)
    |> validate_inclusion(:detected_by, ~w(auto manual))
  end
end
