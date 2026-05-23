defmodule AgenticAiAgent.Traces.ToolCall do
  use Ecto.Schema
  import Ecto.Changeset

  alias AgenticAiAgent.Traces.{Run, Step}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "tool_calls" do
    belongs_to :run, Run
    belongs_to :step, Step
    field :tool_name, :string
    field :input, :map
    field :output, :map
    field :error, :string
    field :latency_ms, :integer

    timestamps(type: :utc_datetime)
  end

  @castable ~w(run_id step_id tool_name input output error latency_ms)a

  def changeset(tc, attrs) do
    tc
    |> cast(attrs, @castable)
    |> validate_required([:run_id, :tool_name])
  end
end
