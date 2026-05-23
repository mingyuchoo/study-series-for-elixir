defmodule AgenticAiAgent.Design.AgenticCard do
  use Ecto.Schema
  import Ecto.Changeset

  alias AgenticAiAgent.Design.{CapabilityMatrix, TaskTaxonomy, WorkflowGraph}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "agentic_cards" do
    field :slug, :string
    field :name, :string
    field :role, :string
    field :goal, :string
    field :scope, :string
    field :capabilities, :map
    field :tool_policy, :map
    field :reasoning_policy, :map
    field :safety_policy, :map
    field :output_contract, :map
    field :evaluation_mapping, :map
    field :metadata, :map

    has_many :task_taxonomies, TaskTaxonomy
    has_one :capability_matrix, CapabilityMatrix
    has_many :workflow_graphs, WorkflowGraph

    timestamps(type: :utc_datetime)
  end

  @castable ~w(slug name role goal scope capabilities tool_policy reasoning_policy safety_policy output_contract evaluation_mapping metadata)a

  def changeset(card, attrs) do
    card
    |> cast(attrs, @castable)
    |> validate_required([:slug, :name])
    |> unique_constraint(:slug)
  end
end
