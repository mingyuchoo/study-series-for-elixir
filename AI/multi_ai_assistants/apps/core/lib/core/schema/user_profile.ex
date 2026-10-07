defmodule Core.Schema.UserProfile do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "user_profiles" do
    field(:data, :map, default: %{})
    belongs_to(:user, Core.Schema.User)
    timestamps(type: :utc_datetime)
  end

  def changeset(profile, attrs) do
    profile
    |> cast(attrs, [:user_id, :data])
    |> validate_required([:user_id, :data])
    |> unique_constraint(:user_id)
    |> foreign_key_constraint(:user_id)
  end
end
