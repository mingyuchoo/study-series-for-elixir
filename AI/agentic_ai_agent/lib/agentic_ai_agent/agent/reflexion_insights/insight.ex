defmodule AgenticAiAgent.Agent.ReflexionInsights.Insight do
  @moduledoc """
  One per-run self-critique with a coarse extracted `theme`. Drives the
  recurring-pattern detector that bridges Reflexion → Improver.

  Distinct from `AgenticAiAgent.Memory` rows: those are for semantic
  retrieval at chat time, this is for structured aggregation at
  improvement time. See `AgenticAiAgent.Agent.ReflexionInsights` for
  the operations.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias AgenticAiAgent.Improver.Proposal
  alias AgenticAiAgent.Traces.Run

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "reflexion_insights" do
    belongs_to :run, Run
    field :card_slug, :string
    field :critique, :string
    field :theme, :string
    belongs_to :triggered_proposal, Proposal, foreign_key: :triggered_proposal_id

    timestamps(type: :utc_datetime)
  end

  @castable ~w(run_id card_slug critique theme triggered_proposal_id)a

  def changeset(insight, attrs) do
    insight
    |> cast(attrs, @castable)
    |> validate_required([:critique])
  end
end
