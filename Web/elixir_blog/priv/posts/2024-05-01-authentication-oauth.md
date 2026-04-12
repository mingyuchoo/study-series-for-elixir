---
title: "OAuth 2.0와 OpenID Connect 구현"
author: "임동현"
tags: ["authentication", "security", "web-dev"]
thumbnail: "/images/thumbnails/oauth-openid.jpg"
summary: "Phoenix에서 OAuth 2.0과 OpenID Connect를 구현하는 방법을 배웁니다."
published_at: 2024-05-01T09:30:00Z
is_popular: false
---

OAuth 2.0과 OpenID Connect는 현대적인 인증 표준입니다. Phoenix에서 이를 구현해봅시다.

## OAuth 2.0 기본

### Google OAuth 구현

```elixir
# config/config.exs
config :ueberauth, Ueberauth,
  providers: [
    google: {Ueberauth.Strategy.Google, [
      client_id: System.get_env("GOOGLE_CLIENT_ID"),
      client_secret: System.get_env("GOOGLE_CLIENT_SECRET")
    ]}
  ]
```

### Ueberauth를 이용한 인증

```elixir
# lib/myapp_web/controllers/auth_controller.ex
defmodule MyappWeb.AuthController do
  use MyappWeb, :controller
  plug Ueberauth

  def callback(%{assigns: %{ueberauth_failure: _fails}} = conn, _params) do
    conn
    |> put_flash(:error, "Failed to authenticate.")
    |> redirect(to: "/")
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    case register_or_sign_in(auth) do
      {:ok, user} ->
        conn
        |> put_session(:user_id, user.id)
        |> put_flash(:info, "Successfully authenticated.")
        |> redirect(to: "/dashboard")
      {:error, reason} ->
        conn
        |> put_flash(:error, reason)
        |> redirect(to: "/")
    end
  end

  defp register_or_sign_in(auth) do
    case Repo.get_by(User, email: auth.info.email) do
      nil -> create_user_from_auth(auth)
      user -> {:ok, user}
    end
  end

  defp create_user_from_auth(auth) do
    attrs = %{
      email: auth.info.email,
      name: auth.info.name,
      provider: Atom.to_string(auth.provider),
      provider_uid: auth.uid
    }

    User.changeset(%User{}, attrs)
    |> Repo.insert()
  end
end
```

## JWT 토큰 관리

```elixir
# lib/myapp/auth/token.ex
defmodule Myapp.Auth.Token do
  use Joken.Config

  add_hook(JokenConfig, :verify_and_validate, {Myapp.Auth.TokenHooks, :verify})

  def token_config do
    default_claims(
      aud: "myapp",
      iss: "myapp"
    )
    |> add_claim("user_id", nil, &is_integer/1)
    |> add_claim("email", nil, &is_binary/1)
  end

  def generate_tokens(user) do
    {:ok, access_token, _claims} = generate_and_sign(
      %{user_id: user.id, email: user.email},
      Joken.Config.default_signer()
    )

    {:ok, refresh_token, _claims} = generate_and_sign(
      %{user_id: user.id, type: "refresh"},
      Joken.Config.default_signer()
    )

    {:ok, access_token, refresh_token}
  end

  def verify_token(token) do
    verify_and_validate(token, Joken.Config.default_signer())
  end
end
```

## 인증 플러그

```elixir
# lib/myapp_web/plugs/authenticate.ex
defmodule MyappWeb.Plugs.Authenticate do
  import Plug.Conn

  def init(options) do
    options
  end

  def call(conn, _opts) do
    with auth_header <- get_req_header(conn, "authorization"),
         [bearer, token] <- String.split(Enum.at(auth_header, 0) || "", " "),
         "Bearer" <- bearer,
         {:ok, claims} <- Myapp.Auth.Token.verify_token(token) do
      assign(conn, :current_user, claims)
    else
      _ ->
        conn
        |> put_status(401)
        |> Phoenix.Controller.json(%{error: "Unauthorized"})
        |> halt()
    end
  end
end
```

## 소셜 로그인

```elixir
# lib/myapp_web/router.ex
defmodule MyappWeb.Router do
  use MyappWeb, :router

  scope "/auth", MyappWeb do
    pipe_through :browser

    get "/login/:provider", AuthController, :request
    get "/callback/:provider", AuthController, :callback
  end
end
```

## 관리자 권한

```elixir
# lib/myapp/auth/permissions.ex
defmodule Myapp.Auth.Permissions do
  def has_permission?(user, permission) do
    user.role == "admin" || Enum.member?(user.permissions, permission)
  end

  def is_admin?(user) do
    user.role == "admin"
  end

  def can_edit_post?(user, post) do
    is_admin?(user) || post.user_id == user.id
  end

  def can_delete_post?(user, post) do
    is_admin?(user) || post.user_id == user.id
  end
end

# 미들웨어
defmodule MyappWeb.Middleware.AuthorizeAdmin do
  import Plug.Conn

  def init(options) do
    options
  end

  def call(conn, _opts) do
    case Myapp.Auth.Permissions.is_admin?(conn.assigns.current_user) do
      true -> conn
      false ->
        conn
        |> put_status(403)
        |> Phoenix.Controller.json(%{error: "Forbidden"})
        |> halt()
    end
  end
end
```

## 세션 관리

```elixir
# lib/myapp_web/plugs/load_user.ex
defmodule MyappWeb.Plugs.LoadUser do
  import Plug.Conn

  def init(options) do
    options
  end

  def call(conn, _opts) do
    user_id = get_session(conn, :user_id)

    if user_id do
      user = Myapp.Repo.get(Myapp.User, user_id)
      assign(conn, :current_user, user)
    else
      assign(conn, :current_user, nil)
    end
  end
end
```

## 로그아웃

```elixir
defmodule MyappWeb.AuthController do
  def logout(conn, _params) do
    conn
    |> clear_session()
    |> redirect(to: "/")
  end
end
```

## 결론

OAuth 2.0과 JWT를 이용한 인증은 안전하고 확장 가능한 인증 시스템을 구축할 수 있게 해줍니다. 적절한 토큰 관리와 권한 확인을 통해 보안이 뛰어난 애플리케이션을 만들 수 있습니다.