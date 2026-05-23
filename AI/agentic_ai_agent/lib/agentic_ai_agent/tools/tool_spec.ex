defmodule AgenticAiAgent.Tools.ToolSpec do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "tool_specs" do
    field :name, :string
    field :purpose, :string
    field :input_schema, :map
    field :output_schema, :map
    field :preconditions, :string
    field :side_effects, :string
    field :failure_modes, {:array, :string}, default: []
    field :retry_policy, :map
    field :risk_level, :string, default: "low"
    field :enabled, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  @castable ~w(name purpose input_schema output_schema preconditions side_effects failure_modes retry_policy risk_level enabled)a

  def changeset(spec, attrs) do
    spec
    |> cast(attrs, @castable)
    |> validate_required([:name])
    |> validate_inclusion(:risk_level, ~w(low medium high critical))
    |> unique_constraint(:name)
  end
end
