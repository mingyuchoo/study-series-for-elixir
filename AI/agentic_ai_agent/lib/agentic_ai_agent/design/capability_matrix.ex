defmodule AgenticAiAgent.Design.CapabilityMatrix do
  use Ecto.Schema
  import Ecto.Changeset

  alias AgenticAiAgent.Design.AgenticCard

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "capability_matrices" do
    belongs_to :agentic_card, AgenticCard
    field :supported_capabilities, {:array, :string}, default: []
    field :supported_inputs, {:array, :string}, default: []
    field :supported_outputs, {:array, :string}, default: []
    field :required_tools, {:array, :string}, default: []
    field :constraints, :string
    field :known_limitations, :string

    timestamps(type: :utc_datetime)
  end

  @castable ~w(agentic_card_id supported_capabilities supported_inputs supported_outputs required_tools constraints known_limitations)a

  def changeset(matrix, attrs) do
    matrix
    |> cast(attrs, @castable)
    |> validate_required([:agentic_card_id])
  end
end
