---
title: "Ecto 고급 쿼리 기술"
author: "정수진"
tags: ["ecto", "database", "elixir"]
thumbnail: "/images/thumbnails/ecto-advanced-queries.jpg"
summary: "Ecto의 고급 쿼리 기능을 마스터하여 복잡한 데이터베이스 작업을 효율적으로 처리합니다."
published_at: 2024-02-20T11:15:00Z
is_popular: false
---

Ecto는 Elixir의 강력한 데이터베이스 라이브러리입니다. 기본 CRUD 작업을 넘어 고급 쿼리 기법을 알아봅시다.

## 복잡한 WHERE 조건

### 여러 조건 결합

```elixir
import Ecto.Query

query = from p in Post,
  where: p.published == true,
  where: p.views > 100,
  where: p.category_id in ^[1, 2, 3],
  select: p

Repo.all(query)
```

### 동적 쿼리 구성

```elixir
def filter_posts(filters) do
  Post
  |> apply_title_filter(filters["title"])
  |> apply_status_filter(filters["status"])
  |> apply_date_filter(filters["from_date"], filters["to_date"])
  |> Repo.all()
end

defp apply_title_filter(query, nil), do: query
defp apply_title_filter(query, title) do
  from p in query, where: like(p.title, ^"%#{title}%")
end

defp apply_status_filter(query, nil), do: query
defp apply_status_filter(query, status) do
  from p in query, where: p.status == ^status
end

defp apply_date_filter(query, nil, nil), do: query
defp apply_date_filter(query, from_date, to_date) do
  from p in query,
    where: p.created_at >= ^from_date and p.created_at <= ^to_date
end
```

## 조인과 관계 활용

### 다양한 조인 타입

```elixir
# INNER JOIN
query = from p in Post,
  join: a in Author, on: p.author_id == a.id,
  select: {p, a}

# LEFT JOIN
query = from p in Post,
  left_join: c in Comment, on: p.id == c.post_id,
  select: {p, c}

# 여러 조인
query = from p in Post,
  join: a in Author, on: p.author_id == a.id,
  join: c in Category, on: p.category_id == c.id,
  select: {p, a, c}

Repo.all(query)
```

## 집계 함수

### COUNT, SUM, AVG 활용

```elixir
# 게시물 개수
from(p in Post, select: count(p.id))
|> Repo.one()

# 총 조회수
from(p in Post, select: sum(p.views))
|> Repo.one()

# 평균 점수
from(p in Post, select: avg(p.rating))
|> Repo.one()

# 그룹별 집계
from(p in Post,
  group_by: p.category_id,
  select: {p.category_id, count(p.id)})
|> Repo.all()
```

## 윈도우 함수

```elixir
query = from p in Post,
  select: %{
    id: p.id,
    title: p.title,
    views: p.views,
    rank: over(
      rank(),
      partition_by: p.category_id,
      order_by: [desc: p.views]
    )
  }

Repo.all(query)
```

## 페이지네이션

```elixir
defmodule PostRepository do
  def paginate(page, per_page \\ 10) do
    offset = (page - 1) * per_page

    query = from p in Post,
      offset: ^offset,
      limit: ^per_page,
      order_by: [desc: p.inserted_at]

    %{
      data: Repo.all(query),
      total: Repo.aggregate(Post, :count, :id),
      page: page,
      per_page: per_page
    }
  end
end
```

## 트랜잭션

```elixir
defmodule PostService do
  def create_with_tags(post_attrs, tag_ids) do
    Repo.transaction(fn ->
      {:ok, post} = Repo.insert(Post.changeset(%Post{}, post_attrs))

      Enum.each(tag_ids, fn tag_id ->
        Repo.insert(%PostTag{post_id: post.id, tag_id: tag_id})
      end)

      post
    end)
  end
end
```

## 대량 작업

```elixir
# 대량 삽입
posts = [
  %{title: "Post 1", content: "..."},
  %{title: "Post 2", content: "..."}
]

Repo.insert_all(Post, posts)

# 대량 업데이트
from(p in Post, where: p.status == "draft")
|> Repo.update_all(set: [status: "published"])

# 대량 삭제
from(p in Post, where: p.created_at < ^old_date)
|> Repo.delete_all()
```

## 성능 최적화 팁

### 1. 필요한 컬럼만 선택

```elixir
# 좋은 예
from(p in Post, select: {p.id, p.title})

# 나쁜 예
from(p in Post, select: p)
```

### 2. 미리 로드 (Preload)

```elixir
posts = from(p in Post, preload: [:author, :comments])
|> Repo.all()
```

## 결론

Ecto의 고급 쿼리 기능을 활용하면 복잡한 데이터 작업을 효율적으로 처리할 수 있습니다. 쿼리 빌더의 강력한 기능들을 이해하고 올바르게 사용하는 것이 성능과 코드 품질을 높이는 핵심입니다.