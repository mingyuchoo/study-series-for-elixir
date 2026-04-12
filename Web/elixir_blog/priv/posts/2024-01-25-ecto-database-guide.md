---
title: "Ecto를 활용한 데이터베이스 관리"
author: "박민수"
tags: ["elixir", "ecto", "database"]
thumbnail: "/images/thumbnails/ecto-database.jpg"
summary: "Elixir의 데이터베이스 라이브러리 Ecto를 마스터하고 효율적인 쿼리 작성법을 배웁니다."
published_at: 2024-01-25T14:30:00Z
is_popular: true
---

# Ecto를 활용한 데이터베이스 관리

Ecto는 Elixir 생태계에서 가장 인기 있는 데이터베이스 라이브러리입니다.

## Ecto란?

Ecto는 데이터베이스 wrapper이자 쿼리 빌더, 스키마 관리 도구입니다.

### 주요 컴포넌트

- **Repo**: 데이터베이스 연결 관리
- **Schema**: 데이터 구조 정의
- **Changeset**: 데이터 검증 및 변환
- **Query**: 쿼리 작성 DSL

## 스키마 정의

```elixir
defmodule Blog.Post do
  use Ecto.Schema

  schema "posts" do
    field :title, :string
    field :content, :text
    field :published_at, :utc_datetime

    belongs_to :author, Blog.Author
    many_to_many :tags, Blog.Tag, join_through: "posts_tags"

    timestamps()
  end
end
```

## Changeset을 통한 검증

```elixir
def changeset(post, attrs) do
  post
  |> cast(attrs, [:title, :content, :published_at])
  |> validate_required([:title, :content])
  |> validate_length(:title, min: 5, max: 100)
  |> unique_constraint(:title)
end
```

## 쿼리 작성

Ecto는 강력한 쿼리 DSL을 제공합니다.

```elixir
import Ecto.Query

query = from p in Post,
  where: p.published_at < ^DateTime.utc_now(),
  order_by: [desc: p.published_at],
  preload: [:author, :tags],
  limit: 10

Repo.all(query)
```

## 마이그레이션

데이터베이스 스키마 변경은 마이그레이션을 통해 관리합니다.

```elixir
defmodule Blog.Repo.Migrations.CreatePosts do
  use Ecto.Migration

  def change do
    create table(:posts) do
      add :title, :string, null: false
      add :content, :text
      add :author_id, references(:authors)

      timestamps()
    end

    create index(:posts, [:author_id])
  end
end
```

## 트랜잭션

복잡한 작업은 트랜잭션으로 묶어 원자성을 보장합니다.

```elixir
Repo.transaction(fn ->
  post = Repo.insert!(%Post{title: "새 글"})
  Repo.update!(Post.changeset(post, %{published: true}))
end)
```

## 결론

Ecto는 type-safe하고 컴포저블한 쿼리 작성을 가능하게 하며, Elixir 애플리케이션의 데이터 레이어를 견고하게 만들어줍니다.
