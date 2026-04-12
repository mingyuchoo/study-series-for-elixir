defmodule ElixirBlog.Blog do
  @moduledoc """
  The Blog context provides functions for querying and managing blog posts,
  tags, and subscriptions.
  """

  import Ecto.Query, warn: false
  alias ElixirBlog.Repo
  alias ElixirBlog.Blog.{Post, Tag, Subscription}

  # Post queries

  @doc """
  Returns a list of popular posts for carousel and popular grid.
  Posts are filtered by is_popular flag and ordered by published_at descending.

  ## Options

    * `:limit` - Maximum number of posts to return (default: 10)

  ## Examples

      iex> Blog.list_popular_posts(limit: 5)
      [%Post{}, ...]
  """
  def list_popular_posts(opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)

    from(p in Post,
      where: p.is_popular == true,
      order_by: [desc: p.published_at],
      limit: ^limit,
      preload: [:tags]
    )
    |> Repo.all()
  end

  @doc """
  Returns a list of posts filtered by category/tag slug.

  ## Options

    * `:limit` - Maximum number of posts to return (default: 12)

  ## Examples

      iex> Blog.list_posts_by_category("elixir")
      [%Post{}, ...]
  """
  def list_posts_by_category(tag_slug, opts \\ []) do
    limit = Keyword.get(opts, :limit, 12)

    from(p in Post,
      join: t in assoc(p, :tags),
      where: t.slug == ^tag_slug,
      order_by: [desc: p.published_at],
      limit: ^limit,
      preload: [:tags]
    )
    |> Repo.all()
  end

  @doc """
  Returns all posts ordered by published_at descending.

  ## Options

    * `:limit` - Maximum number of posts to return (default: 50)

  ## Examples

      iex> Blog.list_posts()
      [%Post{}, ...]
  """
  def list_posts(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    from(p in Post,
      order_by: [desc: p.published_at],
      limit: ^limit,
      preload: [:tags]
    )
    |> Repo.all()
  end

  @doc """
  Returns all posts without limit for sitemap generation.
  Posts are ordered by published_at descending.

  ## Examples

      iex> Blog.list_all_posts()
      [%Post{}, ...]
  """
  def list_all_posts do
    from(p in Post,
      order_by: [desc: p.published_at],
      preload: [:tags]
    )
    |> Repo.all()
  end

  @doc """
  Gets a single post by slug.

  Returns `nil` if the post does not exist.

  ## Examples

      iex> Blog.get_post_by_slug("my-first-post")
      %Post{}

      iex> Blog.get_post_by_slug("non-existent")
      nil
  """
  def get_post_by_slug(slug) do
    from(p in Post,
      where: p.slug == ^slug,
      preload: [:tags]
    )
    |> Repo.one()
  end

  @doc """
  Gets a single post by slug, raises if not found.

  ## Examples

      iex> Blog.get_post_by_slug!("my-first-post")
      %Post{}

      iex> Blog.get_post_by_slug!("non-existent")
      ** (Ecto.NoResultsError)
  """
  def get_post_by_slug!(slug) do
    from(p in Post,
      where: p.slug == ^slug,
      preload: [:tags]
    )
    |> Repo.one!()
  end

  # Tag queries

  @doc """
  Returns all tags with post counts, optionally sorted.

  ## Options

    * `:sort` - Sorting strategy (default: `:alphabetical`)
      - `:alphabetical` - Sort by tag name (A-Z, 가-힣)
      - `:post_count` - Sort by post count (descending)

  ## Examples

      iex> Blog.list_tags_with_post_counts()
      [%{id: 1, name: "Elixir", slug: "elixir", post_count: 15}, ...]

      iex> Blog.list_tags_with_post_counts(sort: :post_count)
      [%{id: 3, name: "Phoenix", slug: "phoenix", post_count: 42}, ...]
  """
  def list_tags_with_post_counts(opts \\ []) do
    sort_by = Keyword.get(opts, :sort, :alphabetical)

    # Subquery to count posts per tag
    post_counts =
      from(pt in "post_tags",
        group_by: pt.tag_id,
        select: %{tag_id: pt.tag_id, post_count: count(pt.post_id)}
      )

    # Main query joining tags with post counts
    query =
      from(t in Tag,
        left_join: pc in subquery(post_counts),
        on: t.id == pc.tag_id,
        select: %{
          id: t.id,
          name: t.name,
          slug: t.slug,
          post_count: coalesce(pc.post_count, 0)
        }
      )

    # Apply sorting
    query =
      case sort_by do
        :alphabetical -> order_by(query, [t], asc: t.name)
        :post_count -> order_by(query, [t, pc], desc: coalesce(pc.post_count, 0))
      end

    Repo.all(query)
  end

  @doc """
  Returns all tags ordered by name.

  ## Examples

      iex> Blog.list_tags()
      [%Tag{}, ...]
  """
  def list_tags do
    from(t in Tag, order_by: t.name)
    |> Repo.all()
  end

  @doc """
  Gets a single tag by slug.

  Returns `nil` if the tag does not exist.

  ## Examples

      iex> Blog.get_tag_by_slug("elixir")
      %Tag{}

      iex> Blog.get_tag_by_slug("non-existent")
      nil
  """
  def get_tag_by_slug(slug) do
    from(t in Tag, where: t.slug == ^slug)
    |> Repo.one()
  end

  @doc """
  Gets or creates a tag by name and slug.

  ## Examples

      iex> Blog.get_or_create_tag("Elixir", "elixir")
      {:ok, %Tag{}}
  """
  def get_or_create_tag(name, slug) do
    case Repo.get_by(Tag, slug: slug) do
      nil ->
        %Tag{}
        |> Tag.changeset(%{name: name, slug: slug})
        |> Repo.insert()

      tag ->
        {:ok, tag}
    end
  end

  # Subscription queries

  @doc """
  Creates a new subscription.

  ## Examples

      iex> Blog.create_subscription(%{email: "user@example.com"})
      {:ok, %Subscription{}}

      iex> Blog.create_subscription(%{email: "invalid"})
      {:error, %Ecto.Changeset{}}
  """
  def create_subscription(attrs \\ %{}) do
    %Subscription{}
    |> Subscription.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking subscription changes.

  ## Examples

      iex> Blog.change_subscription(subscription)
      %Ecto.Changeset{data: %Subscription{}}
  """
  def change_subscription(%Subscription{} = subscription, attrs \\ %{}) do
    Subscription.changeset(subscription, attrs)
  end

  @doc """
  Checks if an email is already subscribed.

  ## Examples

      iex> Blog.email_subscribed?("user@example.com")
      true
  """
  def email_subscribed?(email) do
    from(s in Subscription, where: s.email == ^email)
    |> Repo.exists?()
  end
end
