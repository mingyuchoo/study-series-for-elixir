---
title: "Elixir 프로젝트 코드 조직화"
author: "송태양"
tags: ["architecture", "elixir", "programming"]
thumbnail: "/images/thumbnails/code-organization.jpg"
summary: "확장 가능하고 유지보수하기 쉬운 Elixir 프로젝트 구조를 설계합니다."
published_at: 2024-05-10T10:45:00Z
is_popular: false
---

프로젝트 구조는 코드 관리와 유지보수의 기초입니다. 효과적인 코드 조직화 방법을 알아봅시다.

## 디렉토리 구조

```
myapp/
├── lib/
│   ├── myapp/
│   │   ├── application.ex
│   │   ├── repo.ex
│   │   ├── contexts/
│   │   │   ├── accounts/
│   │   │   │   ├── user.ex
│   │   │   │   └── accounts.ex
│   │   │   ├── posts/
│   │   │   │   ├── post.ex
│   │   │   │   └── posts.ex
│   │   │   └── comments/
│   │   │       ├── comment.ex
│   │   │       └── comments.ex
│   │   ├── services/
│   │   │   └── email_service.ex
│   │   └── utils/
│   │       └── string_helpers.ex
│   └── myapp_web/
│       ├── endpoint.ex
│       ├── router.ex
│       ├── controllers/
│       ├── views/
│       ├── templates/
│       ├── channels/
│       └── live/
├── test/
├── config/
└── priv/
```

## Context 패턴

```elixir
# lib/myapp/accounts/accounts.ex
defmodule Myapp.Accounts do
  alias Myapp.Accounts.User
  alias Myapp.Repo

  def create_user(attrs) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  def get_user(id) do
    Repo.get(User, id)
  end

  def list_users do
    Repo.all(User)
  end

  def update_user(user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  def delete_user(user) do
    Repo.delete(user)
  end

  def authenticate_user(email, password) do
    user = Repo.get_by(User, email: email)

    case user do
      nil ->
        {:error, "Invalid credentials"}
      user ->
        if User.verify_password(password, user.password_hash) do
          {:ok, user}
        else
          {:error, "Invalid credentials"}
        end
    end
  end
end
```

## 스키마 분리

```elixir
# lib/myapp/accounts/user.ex
defmodule Myapp.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :name, :string
    field :password, :string, virtual: true
    field :password_hash, :string

    has_many :posts, Myapp.Posts.Post
    has_many :comments, Myapp.Comments.Comment

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name, :password])
    |> validate_required([:email, :name, :password])
    |> unique_constraint(:email)
    |> put_password_hash()
  end

  defp put_password_hash(changeset) do
    case changeset do
      %Ecto.Changeset{valid?: true, changes: %{password: password}} ->
        put_change(changeset, :password_hash, hash_password(password))
      _ ->
        changeset
    end
  end

  defp hash_password(password) do
    Bcrypt.hash_pwd_salt(password)
  end

  def verify_password(password, hash) do
    Bcrypt.verify_pass(password, hash)
  end
end
```

## 서비스 레이어

```elixir
# lib/myapp/services/email_service.ex
defmodule Myapp.Services.EmailService do
  def send_welcome_email(user) do
    user
    |> welcome_email()
    |> Mailer.deliver()
  end

  def send_password_reset(user, token) do
    user
    |> password_reset_email(token)
    |> Mailer.deliver()
  end

  def send_notification(user, title, message) do
    user
    |> notification_email(title, message)
    |> Mailer.deliver()
  end

  defp welcome_email(user) do
    Swoosh.Email.new()
    |> Swoosh.Email.to({user.name, user.email})
    |> Swoosh.Email.subject("Welcome!")
    |> Swoosh.Email.html_body("<h1>Welcome #{user.name}!</h1>")
  end

  defp password_reset_email(user, token) do
    Swoosh.Email.new()
    |> Swoosh.Email.to({user.name, user.email})
    |> Swoosh.Email.subject("Reset your password")
    |> Swoosh.Email.html_body("""
      <p>Click <a href="#{reset_url(token)}">here</a> to reset your password</p>
    """)
  end

  defp notification_email(user, title, message) do
    Swoosh.Email.new()
    |> Swoosh.Email.to({user.name, user.email})
    |> Swoosh.Email.subject(title)
    |> Swoosh.Email.html_body(message)
  end

  defp reset_url(token) do
    "#{Application.get_env(:myapp, :base_url)}/reset?token=#{token}"
  end
end
```

## 유틸리티 모듈

```elixir
# lib/myapp/utils/string_helpers.ex
defmodule Myapp.Utils.StringHelpers do
  def slugify(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^\w\s-]/, "")
    |> String.replace(~r/[\s_]+/, "-")
    |> String.trim("-")
  end

  def truncate(text, length \\ 100) do
    if String.length(text) > length do
      String.slice(text, 0..(length - 4)) <> "..."
    else
      text
    end
  end

  def highlight_keywords(text, keywords) when is_list(keywords) do
    Enum.reduce(keywords, text, fn keyword, acc ->
      String.replace(acc, keyword, "<mark>#{keyword}</mark>")
    end)
  end
end
```

## 모듈 명명 규칙

```elixir
# 좋은 예
Myapp.Accounts.User
Myapp.Accounts.create_user/1
Myapp.Posts.Post
Myapp.Posts.create_post/1
Myapp.Services.EmailService.send_welcome_email/1

# 피해야 할 예
Myapp.UserService
Myapp.create_user/1
Myapp.PostHelper
```

## 테스트 구조

```
test/
├── myapp/
│   ├── accounts_test.exs
│   ├── posts_test.exs
│   └── services/
│       └── email_service_test.exs
├── myapp_web/
│   ├── controllers/
│   │   └── page_controller_test.exs
│   └── live/
│       └── post_live_test.exs
└── support/
    ├── data_case.ex
    └── conn_case.ex
```

## 의존성 관리

```elixir
# mix.exs
defp deps do
  [
    {:phoenix, "~> 1.7"},
    {:phoenix_html, "~> 3.3"},
    {:phoenix_live_view, "~> 0.19"},
    {:ecto_sql, "~> 3.10"},
    {:postgrex, ">= 0.0.0"},
    {:bcrypt_elixir, "~> 3.0"},
    {:joken, "~> 2.6"},
    {:oban, "~> 2.17"}
  ]
end
```

## 결론

좋은 코드 조직화는 프로젝트의 확장성과 유지보수성을 결정합니다. Context 패턴을 따르고, 명확한 책임 분리를 통해 깔끔하고 관리하기 쉬운 프로젝트를 만들 수 있습니다.