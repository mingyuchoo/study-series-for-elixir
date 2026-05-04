defmodule Core.Schema.Mcp do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "mcps" do
    field(:name, :string)
    field(:command, :string)
    field(:args, {:array, :string}, default: [])
    field(:env, :map, default: %{})
    field(:enabled, :boolean, default: true)

    timestamps(type: :utc_datetime)
  end

  def changeset(mcp, attrs) do
    mcp
    |> cast(attrs, [:name, :command, :args, :env, :enabled])
    |> validate_required([:name, :command])
    |> unique_constraint(:name)
  end
end
