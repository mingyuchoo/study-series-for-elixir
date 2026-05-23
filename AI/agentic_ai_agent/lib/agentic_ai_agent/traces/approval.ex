defmodule AgenticAiAgent.Traces.Approval do
  @moduledoc """
  A pending or resolved human-in-the-loop decision for a single tool call.
  The runtime pauses when a risk-gated tool is about to fire and waits for
  this row to flip from `pending` to `approved` / `denied` / `revised`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias AgenticAiAgent.Traces.{Run, Step}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(pending approved denied revised)

  schema "approvals" do
    belongs_to :run, Run
    belongs_to :step, Step
    field :tool_call_id, :string
    field :tool_name, :string
    field :input, :map
    field :risk_level, :string
    field :status, :string, default: "pending"
    field :revised_input, :map
    field :decided_at, :utc_datetime
    field :decided_by, :string
    field :notes, :string

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  @castable ~w(run_id step_id tool_call_id tool_name input risk_level status revised_input decided_at decided_by notes)a

  def changeset(approval, attrs) do
    approval
    |> cast(attrs, @castable)
    |> validate_required([:run_id, :tool_call_id, :tool_name, :risk_level])
    |> validate_inclusion(:status, @statuses)
  end
end
