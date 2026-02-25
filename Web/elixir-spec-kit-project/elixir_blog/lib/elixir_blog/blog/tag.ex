defmodule ElixirBlog.Blog.Tag do
  use Ecto.Schema
  import Ecto.Changeset

  schema "tags" do
    field :name, :string
    field :slug, :string

    many_to_many :posts, ElixirBlog.Blog.Post, join_through: "post_tags"

    timestamps()
  end

  @required_fields ~w(name slug)a

  def changeset(tag, attrs) do
    tag
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, max: 100)
    |> validate_length(:slug, max: 100)
    |> validate_format(:slug, ~r/^[a-z0-9-]+$/)
    |> unique_constraint(:name)
    |> unique_constraint(:slug)
  end
end
