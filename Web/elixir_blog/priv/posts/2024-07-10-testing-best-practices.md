---
title: "Elixir 테스팅 모범 사례"
author: "이영희"
tags: ["testing", "elixir", "quality"]
thumbnail: "/images/thumbnails/testing-best-practices.jpg"
summary: "효과적인 테스트 작성과 테스트 커버리지 관리 방법을 배웁니다."
published_at: 2024-07-10T10:30:00Z
is_popular: false
---

좋은 테스트는 코드의 품질을 보장합니다. Elixir 테스팅 모범 사례를 알아봅시다.

## 테스트 구조화

```elixir
defmodule UserServiceTest do
  use ExUnit.Case
  doctest UserService

  describe "create_user/1" do
    test "creates a user with valid attributes" do
      attrs = %{"email" => "test@example.com", "name" => "John"}
      {:ok, user} = UserService.create_user(attrs)

      assert user.email == "test@example.com"
      assert user.name == "John"
    end

    test "returns error with invalid email" do
      attrs = %{"email" => "invalid", "name" => "John"}
      {:error, changeset} = UserService.create_user(attrs)

      assert "email" in changeset.errors
    end

    test "returns error with missing name" do
      attrs = %{"email" => "test@example.com"}
      {:error, changeset} = UserService.create_user(attrs)

      assert "name" in changeset.errors
    end
  end

  describe "get_user/1" do
    setup do
      user = create_test_user()
      {:ok, user: user}
    end

    test "returns user by id", %{user: user} do
      result = UserService.get_user(user.id)
      assert result.id == user.id
    end

    test "returns nil for non-existent user" do
      result = UserService.get_user(999999)
      assert is_nil(result)
    end
  end

  defp create_test_user do
    {:ok, user} = UserService.create_user(%{
      "email" => "test@example.com",
      "name" => "John"
    })
    user
  end
end
```

## 픽스처와 헬퍼

```elixir
# test/support/fixtures.ex
defmodule MyApp.Fixtures do
  def user_fixture(attrs \\ %{}) do
    {:ok, user} = %{
      email: "test@example.com",
      name: "Test User"
    }
    |> Enum.into(attrs)
    |> MyApp.Accounts.create_user()

    user
  end

  def post_fixture(user, attrs \\ %{}) do
    {:ok, post} = %{
      user_id: user.id,
      title: "Test Post",
      content: "Test content"
    }
    |> Enum.into(attrs)
    |> MyApp.Posts.create_post()

    post
  end

  def comment_fixture(post, user, attrs \\ %{}) do
    {:ok, comment} = %{
      post_id: post.id,
      user_id: user.id,
      text: "Test comment"
    }
    |> Enum.into(attrs)
    |> MyApp.Comments.create_comment()

    comment
  end
end

# 사용
defmodule PostServiceTest do
  use ExUnit.Case
  import MyApp.Fixtures

  test "creates post with comments" do
    user = user_fixture()
    post = post_fixture(user)
    comment = comment_fixture(post, user)

    assert comment.post_id == post.id
    assert comment.user_id == user.id
  end
end
```

## 비동기 테스트

```elixir
defmodule AsyncProcessTest do
  use ExUnit.Case, async: true

  test "async test 1" do
    assert true
  end

  test "async test 2" do
    assert true
  end
end

defmodule SyncProcessTest do
  use ExUnit.Case, async: false

  test "sync test requires exclusive access" do
    assert true
  end
end
```

## Mock과 Stub

```elixir
defmodule PaymentServiceTest do
  use ExUnit.Case
  import Mox

  setup :verify_on_exit!

  test "processes payment successfully" do
    PaymentGatewayMock
    |> expect(:charge, fn amount ->
      {:ok, %{id: "charge_123", amount: amount}}
    end)

    {:ok, result} = PaymentService.charge(100)
    assert result.id == "charge_123"
    assert result.amount == 100
  end

  test "handles payment failure" do
    PaymentGatewayMock
    |> expect(:charge, fn _amount ->
      {:error, "Card declined"}
    end)

    {:error, reason} = PaymentService.charge(100)
    assert reason == "Card declined"
  end
end
```

## 통합 테스트

```elixir
defmodule UserControllerTest do
  use MyAppWeb.ConnCase

  setup do
    {:ok, user: create_user()}
  end

  describe "POST /api/users" do
    test "creates user with valid attributes", %{conn: conn} do
      conn = post(conn, "/api/users", %{
        "user" => %{
          "email" => "new@example.com",
          "name" => "New User"
        }
      })

      assert json_response(conn, 201)["data"]["id"]
    end

    test "returns error with invalid attributes", %{conn: conn} do
      conn = post(conn, "/api/users", %{
        "user" => %{"email" => "invalid"}
      })

      assert json_response(conn, 422)["errors"]
    end
  end

  describe "GET /api/users/:id" do
    test "returns user", %{conn: conn, user: user} do
      conn = get(conn, "/api/users/#{user.id}")

      assert json_response(conn, 200)["data"]["id"] == user.id
    end
  end

  defp create_user do
    {:ok, user} = Accounts.create_user(%{
      email: "test@example.com",
      name: "Test"
    })
    user
  end
end
```

## 테스트 커버리지

```bash
# mix.exs
def project do
  [
    ...,
    test_coverage: [tool: ExCoveralls],
    preferred_cli_env: [
      coveralls: :test,
      "coveralls.detail": :test,
      "coveralls.post": :test,
      "coveralls.html": :test
    ]
  ]
end
```

```bash
# 커버리지 생성
mix coveralls
mix coveralls.html

# 최소 커버리지 요구
mix coveralls --minimum-coverage 85
```

## 결론

체계적인 테스팅은 코드의 신뢰성을 높이고 버그를 조기에 발견합니다. 단위 테스트, 통합 테스트, 그리고 적절한 모킹을 통해 포괄적인 테스트 스위트를 구축할 수 있습니다.