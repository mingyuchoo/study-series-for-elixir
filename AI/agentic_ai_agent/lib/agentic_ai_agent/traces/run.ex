defmodule AgenticAiAgent.Traces.Run do
  use Ecto.Schema
  import Ecto.Changeset

  alias AgenticAiAgent.Design.AgenticCard
  alias AgenticAiAgent.Traces.{Step, ToolCall}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "runs" do
    belongs_to :agentic_card, AgenticCard
    belongs_to :parent_run, __MODULE__, foreign_key: :parent_run_id
    field :skill_slug, :string
    field :user_input, :string
    field :status, :string, default: "pending"
    field :final_answer, :string
    field :errors, :map
    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec
    field :latency_ms, :integer
    field :cost_cents, :integer
    field :cost_micro_usd, :integer, default: 0
    field :prompt_tokens, :integer, default: 0
    field :completion_tokens, :integer, default: 0

    has_many :steps, Step
    has_many :tool_calls, ToolCall
    has_many :children, __MODULE__, foreign_key: :parent_run_id

    timestamps(type: :utc_datetime)
  end

  @castable ~w(agentic_card_id parent_run_id skill_slug user_input status final_answer errors started_at finished_at latency_ms cost_cents cost_micro_usd prompt_tokens completion_tokens)a

  def changeset(run, attrs) do
    run
    |> cast(attrs, @castable)
    |> validate_inclusion(:status, ~w(pending running awaiting_approval done failed cancelled))
  end
end
