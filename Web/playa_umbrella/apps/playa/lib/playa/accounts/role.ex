defmodule Playa.Accounts.Role do
  use Ecto.Schema
  import Ecto.Changeset

  alias Playa.Accounts.{RoleUser, User}

  @schema_prefix :playa
  schema "roles" do
    field :name, :string
    field :description, :string
    field :user_count, :integer, default: 0
    many_to_many :users, User, join_through: RoleUser, on_replace: :delete
    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(role, attrs) do
    role
    |> cast(attrs, [:name, :description, :user_count])
    |> validate_required([:name, :description])
    |> unique_constraint(:name, name: "roles_name_index")
  end
end
