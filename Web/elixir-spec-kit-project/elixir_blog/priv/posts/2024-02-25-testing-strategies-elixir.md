---
title: "Elixir 테스팅 전략과 ExUnit"
author: "최지훈"
tags: ["testing", "elixir", "programming"]
thumbnail: "/images/thumbnails/testing-strategies.jpg"
summary: "ExUnit을 이용한 효과적인 테스팅 전략을 학습합니다. 단위 테스트부터 통합 테스트까지."
published_at: 2024-02-25T09:45:00Z
is_popular: true
---

Elixir의 테스팅 프레임워크 ExUnit은 매우 강력하고 유연합니다. 효과적인 테스팅 전략을 살펴봅시다.

## ExUnit 기본

### 테스트 구조

```elixir
defmodule UserTest do
  use ExUnit.Case
  doctest User

  setup do
    {:ok, user: %User{name: "John", email: "john@example.com"}}
  end

  test "creates a valid user", %{user: user} do
    assert user.name == "John"
    assert user.email == "john@example.com"
  end

  test "rejects invalid email" do
    {:error, changeset} = User.create(%{name: "John", email: "invalid"})
    assert "email" in changeset.errors
  end
end
```

### 테스트 픽스처

```elixir
defmodule PostTest do
  use ExUnit.Case
  import Fixtures

  setup :create_user

  def create_user(_context) do
    user = insert(:user, name: "Test User")
    {:ok, user: user}
  end

  test "creates a post for user", %{user: user} do
    post = insert(:post, user_id: user.id)
    assert post.user_id == user.id
  end
end
```

## 단위 테스트

### 스키마 테스트

```elixir
defmodule PostValidationTest do
  use ExUnit.Case

  test "validates required fields" do
    changeset = Post.changeset(%Post{}, %{})
    refute changeset.valid?
    assert changeset.errors[:title] != nil
    assert changeset.errors[:content] != nil
  end

  test "validates title length" do
    changeset = Post.changeset(%Post{}, %{"title" => "A"})
    refute changeset.valid?
    assert "should be at least 3 characters" in errors_on(changeset).title
  end

  test "accepts valid attributes" do
    attrs = %{
      title: "Valid Title",
      content: "Valid content here",
      status: "published"
    }
    changeset = Post.changeset(%Post{}, attrs)
    assert changeset.valid?
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
```

## 통합 테스트

### 데이터베이스 테스트

```elixir
defmodule PostRepositoryTest do
  use ExUnit.Case
  import Ecto.Query

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    {:ok, []}
  end

  test "finds published posts" do
    insert_post(title: "Published", status: "published")
    insert_post(title: "Draft", status: "draft")

    published = from(p in Post, where: p.status == "published") |> Repo.all()
    assert length(published) == 1
    assert Enum.at(published, 0).title == "Published"
  end

  defp insert_post(attrs) do
    Repo.insert!(Post.changeset(%Post{}, attrs))
  end
end
```

## Mocking과 Stubbing

### 의존성 주입을 통한 테스트

```elixir
defmodule EmailServiceTest do
  use ExUnit.Case

  test "sends email with correct recipient" do
    mailer = TestMailer
    {:ok, _} = EmailService.send_welcome(mailer, "user@example.com")
  end
end

defmodule TestMailer do
  def send(to, subject, body) do
    {:ok, %{to: to, subject: subject, body: body}}
  end
end
```

### Mox를 이용한 모킹

```elixir
defmodule PaymentServiceTest do
  use ExUnit.Case
  import Mox

  setup :verify_on_exit!

  test "charges card successfully" do
    PaymentGatewayMock
    |> expect(:charge, fn _amount -> {:ok, %{id: "charge_123"}} end)

    {:ok, charge} = PaymentService.process_payment(PaymentGatewayMock, 100)
    assert charge.id == "charge_123"
  end
end
```

## 프로퍼티 기반 테스트

```elixir
defmodule StringUtilsTest do
  use ExUnit.Case
  use PropCheck

  property "reverse twice returns original string" do
    forall s <- string() do
      String.reverse(String.reverse(s)) == s
    end
  end

  property "length stays same after reverse" do
    forall s <- string() do
      String.length(String.reverse(s)) == String.length(s)
    end
  end
end
```

## 테스트 커버리지

```bash
# MIX_ENV=test mix coveralls
# 또는 커버리지 리포트 생성
MIX_ENV=test mix coveralls.html
```

## 결론

효과적인 테스팅은 안정적인 애플리케이션의 기초입니다. ExUnit의 강력한 기능들을 활용하여 다양한 수준의 테스트를 작성하고, 코드의 품질과 신뢰성을 높일 수 있습니다.