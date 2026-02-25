defmodule Core.Schema.Tool do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "tools" do
    field(:name, :string)
    field(:description, :string)
    field(:parameters, :map)
    field(:enabled, :boolean, default: true)

    timestamps(type: :utc_datetime)
  end

  def changeset(tool, attrs) do
    tool
    |> cast(attrs, [:name, :description, :parameters, :enabled])
    |> validate_required([:name, :description, :parameters])
    |> unique_constraint(:name)
  end
end
