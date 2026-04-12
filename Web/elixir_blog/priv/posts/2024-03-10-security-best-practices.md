---
title: "웹 애플리케이션 보안 모범 사례"
author: "임동현"
tags: ["security", "web-dev", "programming"]
thumbnail: "/images/thumbnails/security-best-practices.jpg"
summary: "OWASP Top 10을 기반으로 한 보안 모범 사례를 배웁니다."
published_at: 2024-03-10T14:45:00Z
is_popular: true
---

보안은 모든 웹 애플리케이션의 필수 요소입니다. OWASP Top 10을 기반으로 한 보안 모범 사례를 알아봅시다.

## SQL 인젝션 방지

### 파라미터화된 쿼리

```elixir
# 나쁜 예 - 절대 하지 마세요
query = "SELECT * FROM users WHERE email = '#{email}'"
Ecto.Adapters.SQL.query(Repo, query)

# 좋은 예
from(u in User, where: u.email == ^email)
|> Repo.all()
```

Ecto는 기본적으로 파라미터화된 쿼리를 사용하므로 안전합니다.

## XSS(Cross-Site Scripting) 방지

### HTML 이스케이핑

```elixir
# EEx 템플릿에서 자동 이스케이핑
<%= @user.name %>  <!-- 자동으로 HTML 이스케이핑됨 -->

# 이스케이핑 불필요한 경우
<%= raw(@trusted_html) %>  <!-- 신뢰할 수 있는 HTML만 사용 -->
```

### 콘텐츠 보안 정책 (CSP)

```elixir
# lib/myapp_web/endpoint.ex
plug :put_secure_browser_headers, %{
  "content-security-policy" =>
    "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'"
}
```

## CSRF(Cross-Site Request Forgery) 방지

### CSRF 토큰

```elixir
# Phoenix는 기본적으로 CSRF 보호를 제공합니다
# config/config.exs
config :myapp, MyappWeb.Endpoint,
  csrf_protection: true

# 템플릿에서
<%= hidden_input f, :csrf_token %>
```

## 인증 및 인가

### 안전한 비밀번호 저장

```elixir
defmodule User.Credential do
  def hash_password(password) do
    Bcrypt.hash_pwd_salt(password)
  end

  def verify_password(password, hash) do
    Bcrypt.verify_pass(password, hash)
  end
end

# 사용 예
{:ok, user} = Repo.insert(
  User.changeset(%User{}, %{
    email: "user@example.com",
    password_hash: User.Credential.hash_password("password123")
  })
)

# 검증
User.Credential.verify_password("password123", user.password_hash)
```

### JWT 토큰

```elixir
defmodule AuthToken do
  def generate_token(user_id, opts \\ []) do
    now = System.system_time(:second)
    exp = now + (opts[:expires_in] || 86400)  # 기본 24시간

    claims = %{
      "sub" => user_id,
      "iat" => now,
      "exp" => exp
    }

    {:ok, token, _claims} = Guardian.encode_and_sign(claims)
    token
  end

  def verify_token(token) do
    Guardian.decode_and_verify(token)
  end
end
```

## 데이터 검증 및 새니타이제이션

### 입력 검증

```elixir
defmodule User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :password, :string, virtual: true
    field :password_hash, :string
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :password])
    |> validate_required([:email, :password])
    |> validate_format(:email, ~r/@/)
    |> validate_length(:password, min: 8)
    |> hash_password()
  end

  defp hash_password(changeset) do
    case changeset do
      %Ecto.Changeset{valid?: true, changes: %{password: pwd}} ->
        put_change(changeset, :password_hash, Bcrypt.hash_pwd_salt(pwd))
      _ ->
        changeset
    end
  end
end
```

## 민감한 정보 보호

### 환경 변수 사용

```elixir
# config/runtime.exs
config :myapp, MyappWeb.Endpoint,
  secret_key_base: System.fetch_env!("SECRET_KEY_BASE")

config :myapp, Myapp.Repo,
  url: System.fetch_env!("DATABASE_URL")
```

절대 하드코딩된 시크릿을 사용하지 마세요.

### 로깅 필터

```elixir
# lib/myapp_web/endpoint.ex
defp log_params(params) do
  if Application.get_env(:myapp, :environment) == :prod do
    Enum.map(params, fn
      {"password", _} -> {"password", "***"}
      {"token", _} -> {"token", "***"}
      other -> other
    end)
  else
    params
  end
end
```

## 레이트 제한

### 요청 제한

```elixir
defmodule RateLimiter do
  def check_rate_limit(key, limit \\ 100, window \\ 60) do
    now = System.system_time(:second)
    bucket_key = "rate_limit:#{key}:#{div(now, window)}"

    case Cachex.incr(:cache, bucket_key) do
      {:ok, count} ->
        if count == 1, do: Cachex.expire(:cache, bucket_key, window)
        count <= limit
      _ -> true
    end
  end
end
```

## 결론

보안은 지속적인 노력이 필요합니다. 정기적인 보안 감사, 의존성 업데이트, 그리고 보안 모범 사례를 따르는 것이 중요합니다. Phoenix 프레임워크는 많은 보안 기능을 기본으로 제공하므로, 이를 올바르게 활용하면 안전한 웹 애플리케이션을 만들 수 있습니다.