---
title: "Phoenix에서 GraphQL 구현하기"
author: "윤서연"
tags: ["graphql", "phoenix", "web-dev"]
thumbnail: "/images/thumbnails/graphql-phoenix.jpg"
summary: "Absinthe를 사용한 GraphQL API 구현 방법을 배웁니다."
published_at: 2024-04-25T14:10:00Z
is_popular: true
---

GraphQL은 현대적인 API 쿼리 언어입니다. Absinthe를 이용하여 Phoenix에서 GraphQL을 구현해봅시다.

## Absinthe 설정

```elixir
# mix.exs
defp deps do
  [
    {:absinthe, "~> 1.7"},
    {:absinthe_phoenix, "~> 2.0"}
  ]
end

# config/config.exs
config :myapp, MyappWeb.Endpoint,
  pubsub_server: Myapp.PubSub,
  render_errors: [accepts: ~w(json), default: :json]
```

## 스키마 정의

```elixir
# lib/myapp_web/schema.ex
defmodule MyappWeb.Schema do
  use Absinthe.Schema

  object :post do
    field :id, :id
    field :title, :string
    field :content, :string
    field :author, :user
    field :comments, list_of(:comment)
    field :created_at, :datetime
  end

  object :user do
    field :id, :id
    field :name, :string
    field :email, :string
    field :posts, list_of(:post)
  end

  object :comment do
    field :id, :id
    field :text, :string
    field :author, :user
    field :post, :post
    field :created_at, :datetime
  end

  query do
    field :post, :post do
      arg :id, non_null(:id)
      resolve &Resolvers.Posts.get_post/3
    end

    field :posts, list_of(:post) do
      arg :limit, :integer, default_value: 10
      arg :offset, :integer, default_value: 0
      resolve &Resolvers.Posts.list_posts/3
    end

    field :user, :user do
      arg :id, non_null(:id)
      resolve &Resolvers.Users.get_user/3
    end
  end

  mutation do
    field :create_post, :post do
      arg :title, non_null(:string)
      arg :content, non_null(:string)
      arg :user_id, non_null(:id)
      resolve &Resolvers.Posts.create_post/3
    end

    field :update_post, :post do
      arg :id, non_null(:id)
      arg :title, :string
      arg :content, :string
      resolve &Resolvers.Posts.update_post/3
    end

    field :delete_post, :boolean do
      arg :id, non_null(:id)
      resolve &Resolvers.Posts.delete_post/3
    end
  end
end
```

## 리졸버 구현

```elixir
# lib/myapp_web/resolvers/posts.ex
defmodule MyappWeb.Resolvers.Posts do
  alias Myapp.Repo
  alias Myapp.Post

  def get_post(_parent, %{"id" => id}, _resolution) do
    case Repo.get(Post, id) do
      nil -> {:error, "Post not found"}
      post -> {:ok, post}
    end
  end

  def list_posts(_parent, %{"limit" => limit, "offset" => offset}, _resolution) do
    posts = from(p in Post,
      order_by: [desc: p.inserted_at],
      limit: ^limit,
      offset: ^offset
    ) |> Repo.all()

    {:ok, posts}
  end

  def create_post(_parent, %{"title" => title, "content" => content, "user_id" => user_id}, _resolution) do
    attrs = %{title: title, content: content, user_id: user_id}

    case Repo.insert(Post.changeset(%Post{}, attrs)) do
      {:ok, post} -> {:ok, post}
      {:error, changeset} -> {:error, changeset_errors(changeset)}
    end
  end

  def update_post(_parent, %{"id" => id} = attrs, _resolution) do
    post = Repo.get(Post, id)

    case Repo.update(Post.changeset(post, attrs)) do
      {:ok, post} -> {:ok, post}
      {:error, changeset} -> {:error, changeset_errors(changeset)}
    end
  end

  def delete_post(_parent, %{"id" => id}, _resolution) do
    case Repo.delete(Repo.get(Post, id)) do
      {:ok, _} -> {:ok, true}
      {:error, _} -> {:error, "Failed to delete post"}
    end
  end

  defp changeset_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {key, messages} ->
      "#{key}: #{Enum.join(messages, ", ")}"
    end)
    |> Enum.join("; ")
  end
end
```

## 라우터 설정

```elixir
# lib/myapp_web/router.ex
defmodule MyappWeb.Router do
  use MyappWeb, :router

  scope "/api" do
    pipe_through :api

    forward "/graphql", Absinthe.Plug,
      schema: MyappWeb.Schema

    forward "/graphiql", Absinthe.Plug.GraphiQL,
      schema: MyappWeb.Schema
  end
end
```

## 데이터 로더 (N+1 방지)

```elixir
# lib/myapp_web/schema.ex
defmodule MyappWeb.Schema do
  use Absinthe.Schema
  import Absinthe.Resolution.Helpers

  object :post do
    field :author, :user, resolve: dataloader(:default)
    field :comments, list_of(:comment), resolve: dataloader(:default)
  end

  def context(ctx) do
    loader = Dataloader.new()
      |> Dataloader.add_source(:default, source(:default))

    Map.put(ctx, :loader, loader)
  end

  defp source(:default) do
    Dataloader.Ecto.new(Repo, query: &query/2)
  end

  defp query(Post, _params) do
    Post |> preload(:author)
  end

  defp query(queryable, _params) do
    queryable
  end

  def plugins do
    [Absinthe.Plug.Debug] ++ Absinthe.Plugin.defaults()
  end
end
```

## 인증

```elixir
# lib/myapp_web/middleware/authenticate.ex
defmodule MyappWeb.Middleware.Authenticate do
  @behaviour Absinthe.Middleware

  def call(resolution, _config) do
    case resolution.context do
      %{current_user: _user} ->
        resolution
      _ ->
        resolution
        |> Absinthe.Resolution.put_result({:error, "Unauthenticated"})
    end
  end
end

# 스키마에서 사용
query do
  field :profile, :user do
    middleware MyappWeb.Middleware.Authenticate
    resolve &Resolvers.Users.get_current_user/3
  end
end
```

## 결론

Absinthe를 사용하면 Phoenix에서 강력한 GraphQL API를 빠르게 구축할 수 있습니다. 데이터 로더로 N+1 문제를 해결하고, 미들웨어로 인증을 관리하면 프로덕션 수준의 API를 만들 수 있습니다.