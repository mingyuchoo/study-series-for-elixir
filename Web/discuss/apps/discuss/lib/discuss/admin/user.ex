defmodule Discuss.Admin.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :name, :string
    field :email, :string
    field :role, :string
    field :address, :string
    field :auth_user_id, :integer

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :email, :role, :address, :auth_user_id])
    |> validate_required([:name, :email, :role, :address])
    |> unique_constraint(:email)
  end
end
