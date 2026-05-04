defmodule Core.Schema.Tool do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "tools" do
    field(:name, :string)
    field(:description, :string)
    field(:parameters, :map)
    field(:module_name, :string)
    field(:enabled, :boolean, default: true)

    timestamps(type: :utc_datetime)
  end

  def changeset(tool, attrs) do
    tool
    |> cast(attrs, [:name, :description, :parameters, :module_name, :enabled])
    |> validate_required([:name, :module_name])
    |> unique_constraint(:name)
  end
end
