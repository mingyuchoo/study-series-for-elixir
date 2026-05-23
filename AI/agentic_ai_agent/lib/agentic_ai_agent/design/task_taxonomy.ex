defmodule AgenticAiAgent.Design.TaskTaxonomy do
  use Ecto.Schema
  import Ecto.Changeset

  alias AgenticAiAgent.Design.AgenticCard

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "task_taxonomies" do
    belongs_to :agentic_card, AgenticCard
    field :task_type, :string
    field :domain, :string
    field :complexity, :string
    field :risk_level, :string
    field :required_tools, {:array, :string}, default: []
    field :success_criteria, :string

    timestamps(type: :utc_datetime)
  end

  @castable ~w(agentic_card_id task_type domain complexity risk_level required_tools success_criteria)a

  def changeset(taxonomy, attrs) do
    taxonomy
    |> cast(attrs, @castable)
    |> validate_required([:task_type])
  end
end
