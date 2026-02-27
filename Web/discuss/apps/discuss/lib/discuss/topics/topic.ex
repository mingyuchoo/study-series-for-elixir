defmodule Discuss.Topics.Topic do
  use Ecto.Schema
  import Ecto.Changeset

  schema "topics" do
    field :title, :string
    field :body, :string
    field :auth_user_id, :integer
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(topic, attrs) do
    topic
    |> cast(attrs, [:title, :body, :auth_user_id])
    |> validate_required([:title])
    |> validate_length(:title, min: 2)
    |> validate_length(:title, max: 100)
    |> validate_length(:body, max: 50_000)
  end
end
