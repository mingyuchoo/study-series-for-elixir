---
title: "Phoenix 라우팅 완벽 가이드"
author: "김철수"
tags: ["phoenix", "web-dev", "programming"]
thumbnail: "/images/thumbnails/phoenix-routing-guide.jpg"
summary: "Phoenix 프레임워크의 라우팅 시스템을 깊이 있게 알아봅시다. 라우터 설정부터 고급 기능까지 모두 다룹니다."
published_at: 2024-02-05T09:00:00Z
is_popular: true
---

Phoenix의 라우팅은 웹 애플리케이션의 핵심입니다. 이 글에서는 Phoenix의 강력한 라우팅 시스템을 완벽하게 이해하는 방법을 알아봅니다.

## Phoenix 라우터의 기본 구조

Phoenix 라우터는 `router.ex` 파일에서 정의됩니다. 모든 HTTP 요청은 라우터를 통해 적절한 컨트롤러로 매핑됩니다.

```elixir
defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {MyAppWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", MyAppWeb do
    pipe_through :browser

    get "/", PageController, :home
    resources "/posts", PostController
  end
end
```

이 구조에서 `pipeline`은 모든 요청이 거쳐야 할 중간 처리 단계들을 정의합니다.

## 리소스 라우팅

RESTful API를 쉽게 구성하기 위해 `resources` 매크로를 사용합니다. 이는 7가지 표준 CRUD 액션을 자동으로 생성합니다.

```elixir
scope "/api", MyAppWeb do
  pipe_through :api

  resources "/users", UserController
  resources "/posts", PostController do
    resources "/comments", CommentController
  end
end
```

`resources` 매크로가 생성하는 라우트:
- GET /users → index
- GET /users/new → new
- POST /users → create
- GET /users/:id → show
- GET /users/:id/edit → edit
- PUT /users/:id → update
- DELETE /users/:id → delete

## 경로 매개변수와 동적 라우팅

경로에 매개변수를 포함시켜 동적 라우팅을 구현할 수 있습니다.

```elixir
get "/posts/:id/comments/:comment_id", PostController, :show_comment
get "/categories/:category/posts/:post_id", PostController, :show_by_category
```

컨트롤러에서 접근:

```elixir
def show_comment(conn, %{"id" => post_id, "comment_id" => comment_id}) do
  post = Repo.get!(Post, post_id)
  comment = Repo.get!(Comment, comment_id)
  render(conn, "show.html", post: post, comment: comment)
end
```

## 라우트 헬퍼 함수

Phoenix는 라우트에서 URL을 자동으로 생성하는 헬퍼 함수를 제공합니다.

```elixir
# 라우트 정의
get "/posts/:id", PostController, :show

# 템플릿에서 사용
<a href={~p"/posts/#{@post.id}"}>게시물 보기</a>

# Elixir 코드에서 사용
redirect(conn, to: ~p"/posts/#{post.id}")
```

## 고급 라우팅 기능

### 정규표현식을 이용한 라우팅

```elixir
get "/files/:filename", FileController, :download, constraints: %{"filename" => ~r/\w+\.\w+/}
```

### 동적 경로 세그먼트

```elixir
scope "/admin/:organization_id" do
  get "/dashboard", AdminController, :dashboard
end
```

이는 조직별 관리자 대시보드를 쉽게 구현할 수 있게 합니다.

## 결론

Phoenix의 라우팅 시스템은 강력하고 유연합니다. `resources` 매크로로 RESTful 패턴을 따르고, 필요에 따라 커스텀 라우트를 추가할 수 있습니다. 이 기능들을 잘 활용하면 깔끔하고 유지보수하기 쉬운 웹 애플리케이션을 만들 수 있습니다.