defmodule AgenticAiAgent.Traces.Step do
  use Ecto.Schema
  import Ecto.Changeset

  alias AgenticAiAgent.Traces.{Run, ToolCall}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @kinds ~w(plan act observe reflect llm_call tool_call delegate steer retrieve final)

  schema "steps" do
    belongs_to :run, Run
    field :idx, :integer
    field :kind, :string
    field :payload, :map
    field :latency_ms, :integer
    field :cost_micro_usd, :integer
    field :model, :string
    field :prompt_tokens, :integer
    field :completion_tokens, :integer

    has_many :tool_calls, ToolCall

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds

  @castable ~w(run_id idx kind payload latency_ms cost_micro_usd model prompt_tokens completion_tokens)a

  def changeset(step, attrs) do
    step
    |> cast(attrs, @castable)
    |> validate_required([:run_id, :idx, :kind])
    |> validate_inclusion(:kind, @kinds)
    |> unique_constraint([:run_id, :idx], name: :steps_run_id_idx_index)
  end
end
