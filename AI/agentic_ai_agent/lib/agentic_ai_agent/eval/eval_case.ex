defmodule AgenticAiAgent.Eval.EvalCase do
  use Ecto.Schema
  import Ecto.Changeset

  alias AgenticAiAgent.Eval.EvalRun
  alias AgenticAiAgent.Traces.Run

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "eval_cases" do
    belongs_to :eval_run, EvalRun
    belongs_to :run, Run
    field :case_id, :string
    field :task_type, :string
    field :input, :string
    field :expected, :map
    field :expected_tools, {:array, :string}, default: []
    field :final_answer, :string
    field :scores, :map
    field :total_score, :float
    field :passed, :boolean, default: false
    field :notes, :string

    timestamps(type: :utc_datetime)
  end

  @castable ~w(eval_run_id run_id case_id task_type input expected expected_tools final_answer scores total_score passed notes)a

  def changeset(c, attrs) do
    c
    |> cast(attrs, @castable)
    |> validate_required([:eval_run_id, :case_id])
  end
end
