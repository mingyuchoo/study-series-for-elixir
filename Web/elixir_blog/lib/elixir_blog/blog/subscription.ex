defmodule ElixirBlog.Blog.Subscription do
  use Ecto.Schema
  import Ecto.Changeset

  schema "subscriptions" do
    field :email, :string
    field :subscribed_at, :utc_datetime

    timestamps(updated_at: false)
  end

  @required_fields ~w(email)a

  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/)
    |> validate_length(:email, max: 255)
    |> unique_constraint(:email)
    |> put_subscribed_at()
  end

  defp put_subscribed_at(changeset) do
    if get_change(changeset, :subscribed_at) do
      changeset
    else
      put_change(changeset, :subscribed_at, DateTime.utc_now())
    end
  end
end
