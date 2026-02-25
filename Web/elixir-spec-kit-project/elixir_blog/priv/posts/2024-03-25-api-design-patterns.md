---
title: "RESTful API 설계 패턴과 모범 사례"
author: "김철수"
tags: ["api", "web-dev", "architecture"]
thumbnail: "/images/thumbnails/api-design-patterns.jpg"
summary: "견고하고 확장 가능한 REST API를 설계하기 위한 패턴과 모범 사례를 배웁니다."
published_at: 2024-03-25T15:00:00Z
is_popular: true
---

API 설계는 백엔드 개발의 핵심입니다. 좋은 API 설계 패턴을 따르면 유지보수하기 쉽고 확장 가능한 시스템을 만들 수 있습니다.

## 리소스 중심 설계

### RESTful 엔드포인트

```elixir
# 리소스 표현
GET /posts              # 모든 게시물 조회
GET /posts/:id          # 특정 게시물 조회
POST /posts             # 새 게시물 생성
PUT /posts/:id          # 게시물 전체 업데이트
PATCH /posts/:id        # 게시물 부분 업데이트
DELETE /posts/:id       # 게시물 삭제

# 중첩 리소스
GET /posts/:id/comments        # 게시물의 댓글 조회
POST /posts/:id/comments       # 게시물에 댓글 추가
DELETE /posts/:id/comments/:cid # 댓글 삭제
```

### Phoenix 라우팅 구현

```elixir
scope "/api/v1", MyappWeb.API.V1 do
  pipe_through :api

  resources :posts do
    resources :comments
  end

  resources :users do
    get :profile, on: :member
  end
end
```

## 버전 관리

### URL 경로 기반 버전

```elixir
scope "/api/v1", MyappWeb.API.V1 do
  pipe_through :api
  resources :posts, PostController
end

scope "/api/v2", MyappWeb.API.V2 do
  pipe_through :api
  resources :posts, PostControllerV2
end
```

### 헤더 기반 버전

```elixir
defmodule MyappWeb.VersionRouter do
  def route_by_version(conn) do
    version = get_req_header(conn, "api-version") |> List.first() || "1"

    case version do
      "1" -> MyappWeb.API.V1.PostController
      "2" -> MyappWeb.API.V2.PostController
      _ -> raise "Unsupported API version"
    end
  end
end
```

## 에러 처리

### 일관된 에러 응답

```elixir
defmodule MyappWeb.ErrorView do
  def render("error.json", %{error: error}) do
    %{
      status: error.status,
      code: error.code,
      message: error.message,
      details: error.details
    }
  end
end

# 사용
def show(conn, %{"id" => id}) do
  case Repo.get(Post, id) do
    nil ->
      conn
      |> put_status(404)
      |> render("error.json", %{
        error: %{
          status: 404,
          code: "POST_NOT_FOUND",
          message: "Post not found"
        }
      })
    post ->
      render(conn, "show.json", post: post)
  end
end
```

## 페이지네이션

### 오프셋 기반

```elixir
def index(conn, %{"page" => page, "per_page" => per_page}) do
  page = String.to_integer(page)
  per_page = String.to_integer(per_page)

  posts = from(p in Post,
    offset: ^((page - 1) * per_page),
    limit: ^per_page
  ) |> Repo.all()

  total = Repo.aggregate(Post, :count)

  render(conn, "index.json", %{
    data: posts,
    pagination: %{
      page: page,
      per_page: per_page,
      total: total,
      pages: ceil(total / per_page)
    }
  })
end
```

### 커서 기반 (더 효율적)

```elixir
def index(conn, %{"cursor" => cursor, "limit" => limit}) do
  limit = String.to_integer(limit)

  query = from(p in Post, order_by: [asc: p.id])

  query = if cursor do
    from(p in query, where: p.id > ^cursor)
  else
    query
  end

  posts = query |> limit(^(limit + 1)) |> Repo.all()

  {posts, next_cursor} = if length(posts) > limit do
    {Enum.take(posts, limit), List.last(posts).id}
  else
    {posts, nil}
  end

  render(conn, "index.json", %{
    data: posts,
    next_cursor: next_cursor
  })
end
```

## 필터링 및 정렬

```elixir
def index(conn, params) do
  posts = Post
    |> apply_filters(params)
    |> apply_sort(params)
    |> Repo.all()

  render(conn, "index.json", posts: posts)
end

defp apply_filters(query, params) do
  query
  |> apply_status_filter(params["status"])
  |> apply_category_filter(params["category"])
  |> apply_date_range_filter(params["from_date"], params["to_date"])
end

defp apply_status_filter(query, nil), do: query
defp apply_status_filter(query, status) do
  from(p in query, where: p.status == ^status)
end

defp apply_sort(query, %{"sort" => sort, "order" => order}) do
  sort_field = String.to_atom(sort)
  direction = if order == "desc", do: :desc, else: :asc

  from(p in query, order_by: [{^direction, ^sort_field}])
end

defp apply_sort(query, _), do: query
```

## 요청 검증

```elixir
defmodule MyappWeb.ValidateRequest do
  def validate_params(params, schema) do
    case Ecto.Changeset.cast({%{}, schema}, params, Map.keys(schema)) do
      %Ecto.Changeset{valid?: true, changes: changes} ->
        {:ok, changes}
      %Ecto.Changeset{valid?: false} = changeset ->
        {:error, errors_on(changeset)}
    end
  end
end

# 사용
def create(conn, params) do
  schema = %{
    title: :string,
    content: :string
  }

  case ValidateRequest.validate_params(params, schema) do
    {:ok, valid_params} ->
      # 게시물 생성
      {:ok, post} = Repo.insert(Post.changeset(%Post{}, valid_params))
      render(conn, "show.json", post: post)
    {:error, errors} ->
      conn
      |> put_status(422)
      |> render("error.json", %{error: errors})
  end
end
```

## 결론

좋은 API 설계는 클라이언트의 개발을 쉽게 하고, 유지보수를 간단하게 합니다. RESTful 원칙을 따르고, 일관된 에러 처리, 적절한 버전 관리를 통해 장기적으로 성장할 수 있는 API를 설계하세요.