defmodule AgenticAiAgent.Eval.EvalRun do
  use Ecto.Schema
  import Ecto.Changeset

  alias AgenticAiAgent.Design.AgenticCard
  alias AgenticAiAgent.Eval.EvalCase

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "eval_runs" do
    belongs_to :agentic_card, AgenticCard
    field :golden_path, :string
    field :rubric, :map
    field :pass_threshold, :float
    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec
    field :total_cases, :integer, default: 0
    field :passed_cases, :integer, default: 0
    field :average_score, :float
    field :status, :string, default: "running"
    field :summary, :map

    has_many :cases, EvalCase

    timestamps(type: :utc_datetime)
  end

  @castable ~w(agentic_card_id golden_path rubric pass_threshold started_at finished_at total_cases passed_cases average_score status summary)a

  def changeset(run, attrs) do
    run
    |> cast(attrs, @castable)
    |> validate_inclusion(:status, ~w(running done failed))
  end
end
