defmodule ElixirBlog.Blog.Post do
  use Ecto.Schema
  import Ecto.Changeset

  schema "posts" do
    field :slug, :string
    field :title, :string
    field :author, :string
    field :summary, :string
    field :thumbnail, :string
    field :published_at, :utc_datetime
    field :is_popular, :boolean, default: false
    field :reading_time, :integer
    field :content_path, :string

    many_to_many :tags, ElixirBlog.Blog.Tag, join_through: "post_tags"

    timestamps()
  end

  @required_fields ~w(slug title author summary thumbnail published_at reading_time content_path)a
  @optional_fields ~w(is_popular)a

  def changeset(post, attrs) do
    post
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:slug, min: 1, max: 255)
    |> validate_length(:title, max: 500)
    |> validate_length(:author, max: 255)
    |> validate_length(:summary, max: 1000)
    |> validate_number(:reading_time, greater_than: 0)
    |> validate_format(:slug, ~r/^[a-z0-9-]+$/)
    |> unique_constraint(:slug)
    |> unique_constraint(:content_path)
  end
end
