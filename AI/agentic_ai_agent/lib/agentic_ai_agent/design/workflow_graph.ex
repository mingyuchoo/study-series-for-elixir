defmodule AgenticAiAgent.Design.WorkflowGraph do
  use Ecto.Schema
  import Ecto.Changeset

  alias AgenticAiAgent.Design.AgenticCard

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "workflow_graphs" do
    belongs_to :agentic_card, AgenticCard
    field :name, :string
    field :states, :map
    field :transitions, :map
    field :terminal_states, {:array, :string}, default: []
    field :approval_points, {:array, :string}, default: []
    field :enforce, :boolean, default: false
    field :allowed_actions, :map
    field :required_evidence, :map

    timestamps(type: :utc_datetime)
  end

  @castable ~w(agentic_card_id name states transitions terminal_states approval_points enforce allowed_actions required_evidence)a

  def changeset(graph, attrs) do
    graph
    |> cast(attrs, @castable)
    |> validate_required([:agentic_card_id, :name])
  end
end
