defmodule AgenticAiAgent.Improver.SchedulerDecisions.Decision do
  @moduledoc """
  One persisted record of a decision the `Improver.Scheduler` reached on
  one staging eval — whether it actually mutated production or not.

  Distinct from `Notifications.Notification`: notifications are operator
  alerts that get marked read and pruned; decisions are an audit log
  for "what did autonomy do?", queried via
  `AgenticAiAgent.Improver.SchedulerDecisions`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias AgenticAiAgent.Improver.Proposal

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @actions ~w(applied rolled_back blocked_safety blocked_perf would_apply
              would_rollback rollback_safety_warning no_previous_version
              restore_failed)

  schema "scheduler_decisions" do
    field :action, :string
    field :dry_run, :boolean, default: false
    field :card_slug, :string
    field :detail, :string
    field :metadata, :map

    belongs_to :proposal, Proposal, foreign_key: :proposal_id

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def actions, do: @actions

  @castable ~w(action dry_run card_slug detail metadata proposal_id)a

  def changeset(decision, attrs) do
    decision
    |> cast(attrs, @castable)
    |> validate_required([:action])
    |> validate_inclusion(:action, @actions)
  end
end
