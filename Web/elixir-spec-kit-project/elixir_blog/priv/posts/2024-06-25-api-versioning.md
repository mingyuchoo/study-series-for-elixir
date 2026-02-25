---
title: "API 버전 관리 전략"
author: "한예진"
tags: ["api", "web-dev", "architecture"]
thumbnail: "/images/thumbnails/api-versioning.jpg"
summary: "호환성을 유지하면서 API를 진화시키는 버전 관리 전략을 배웁니다."
published_at: 2024-06-25T10:15:00Z
is_popular: true
---

API는 지속적으로 진화하며, 버전 관리는 이 과정에서 중요합니다. 효과적인 버전 관리 전략을 알아봅시다.

## URL 경로 기반 버전 관리

```elixir
# lib/myapp_web/router.ex
defmodule MyappWeb.Router do
  use MyappWeb, :router

  scope "/api/v1", MyappWeb.API.V1 do
    pipe_through :api

    resources :posts, PostController
    resources :users, UserController
  end

  scope "/api/v2", MyappWeb.API.V2 do
    pipe_through :api

    resources :posts, PostController
    resources :users, UserController
  end
end
```

## 헤더 기반 버전 관리

```elixir
# lib/myapp_web/plugs/api_version.ex
defmodule MyappWeb.Plugs.ApiVersion do
  import Plug.Conn

  def init(options) do
    options
  end

  def call(conn, _opts) do
    version = get_req_header(conn, "api-version") |> List.first() || "1"

    assign(conn, :api_version, version)
  end
end

# 컨트롤러
defmodule MyappWeb.API.PostController do
  use MyappWeb, :controller

  def show(conn, %{"id" => id}) do
    post = Repo.get!(Post, id)

    case conn.assigns.api_version do
      "1" -> render(conn, "show_v1.json", post: post)
      "2" -> render(conn, "show_v2.json", post: post)
      _ -> render(conn, "show_v1.json", post: post)
    end
  end
end
```

## 요청 바디 변환

```elixir
defmodule ApiAdapter do
  def adapt_request(conn, version) do
    case version do
      "1" -> V1.RequestAdapter.adapt(conn)
      "2" -> V2.RequestAdapter.adapt(conn)
      _ -> conn
    end
  end

  def adapt_response(data, version) do
    case version do
      "1" -> V1.ResponseAdapter.adapt(data)
      "2" -> V2.ResponseAdapter.adapt(data)
      _ -> data
    end
  end
end

# V1 응답 형식
defmodule V1.ResponseAdapter do
  def adapt(post) do
    %{
      id: post.id,
      title: post.title,
      content: post.content,
      created_at: DateTime.to_iso8601(post.created_at)
    }
  end
end

# V2 응답 형식
defmodule V2.ResponseAdapter do
  def adapt(post) do
    %{
      id: post.id,
      title: post.title,
      body: post.content,  # content -> body로 변경
      metadata: %{
        created: DateTime.to_iso8601(post.created_at),
        updated: DateTime.to_iso8601(post.updated_at)
      }
    }
  end
end
```

## 폐기 예정(Deprecation) 관리

```elixir
defmodule MyappWeb.Plugs.DeprecationWarning do
  import Plug.Conn

  def init(options) do
    options
  end

  def call(conn, _opts) do
    version = conn.assigns.api_version

    if should_warn?(version) do
      add_deprecation_header(conn, version)
    else
      conn
    end
  end

  defp should_warn?(version) do
    version in ["1", "1.1"]
  end

  defp add_deprecation_header(conn, version) do
    put_resp_header(
      conn,
      "deprecation",
      "true"
    )
    |> put_resp_header(
      "sunset",
      "Sun, 01 Jan 2025 00:00:00 GMT"
    )
    |> put_resp_header(
      "x-api-warn",
      "API v#{version} is deprecated. Use v2 instead."
    )
  end
end
```

## 마이그레이션 가이드

```elixir
# lib/myapp_web/controllers/migration_controller.ex
defmodule MyappWeb.MigrationController do
  use MyappWeb, :controller

  def v1_to_v2(conn, _params) do
    guide = """
    # API v1 에서 v2로 마이그레이션

    ## 주요 변경사항

    ### 1. 필드명 변경
    - `content` -> `body`
    - `created_at` -> `metadata.created`

    ### 2. 응답 구조
    V1:
    ```json
    {
      "id": 1,
      "title": "Post",
      "content": "Content",
      "created_at": "2024-01-01T00:00:00Z"
    }
    ```

    V2:
    ```json
    {
      "id": 1,
      "title": "Post",
      "body": "Content",
      "metadata": {
        "created": "2024-01-01T00:00:00Z",
        "updated": "2024-01-01T00:00:00Z"
      }
    }
    ```

    ### 3. 엔드포인트
    - `/api/v1/*` -> `/api/v2/*`
    - 요청 헤더: `Api-Version: 2`
    """

    json(conn, %{migration_guide: guide})
  end
end
```

## 호환성 레이어

```elixir
defmodule CompatibilityLayer do
  def handle_v1_request(request, processor) do
    # V1 요청을 V2 포맷으로 변환
    v2_request = convert_to_v2(request)

    # V2 로직 실행
    response = processor.(v2_request)

    # V1 응답으로 변환
    convert_to_v1(response)
  end

  defp convert_to_v2(%{"content" => content} = request) do
    request
    |> Map.delete("content")
    |> Map.put("body", content)
  end

  defp convert_to_v2(request), do: request

  defp convert_to_v1(%{"body" => body} = response) do
    response
    |> Map.delete("body")
    |> Map.put("content", body)
  end

  defp convert_to_v1(response), do: response
end
```

## 결론

좋은 버전 관리 전략은 기존 클라이언트와의 호환성을 유지하면서도 API를 진화시킬 수 있게 합니다. 명확한 버전 관리 정책과 마이그레이션 가이드를 제공하면 더 나은 사용자 경험을 제공할 수 있습니다.