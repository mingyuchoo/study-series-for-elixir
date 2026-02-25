---
title: "Elixir에서 의존성 주입 패턴"
author: "이영희"
tags: ["elixir", "programming", "architecture"]
thumbnail: "/images/thumbnails/dependency-injection.jpg"
summary: "테스트 가능하고 유연한 코드를 위한 의존성 주입 패턴을 배웁니다."
published_at: 2024-05-20T09:15:00Z
is_popular: false
---

의존성 주입은 느슨한 결합과 높은 테스트 가능성을 제공합니다. Elixir에서 의존성 주입을 구현해봅시다.

## 기본 패턴

```elixir
# lib/myapp/services/user_service.ex
defmodule Myapp.Services.UserService do
  # 의존성을 인자로 받음
  def create_user(user_attrs, repo \\ Myapp.Repo) do
    attrs = %{
      email: user_attrs[:email],
      name: user_attrs[:name]
    }

    case repo.insert(User.changeset(%User{}, attrs)) do
      {:ok, user} -> {:ok, user}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def get_user(id, repo \\ Myapp.Repo) do
    repo.get(User, id)
  end
end

# 테스트
defmodule UserServiceTest do
  use ExUnit.Case

  defmodule MockRepo do
    def insert(_), do: {:ok, %User{id: 1}}
    def get(User, _id), do: %User{id: 1}
  end

  test "creates user with mock repo" do
    {:ok, user} = UserService.create_user(%{email: "test@example.com"}, MockRepo)
    assert user.id == 1
  end
end
```

## 고차 함수를 이용한 주입

```elixir
defmodule EmailService do
  def send_welcome(mailer_fn, user) do
    email_content = "Welcome #{user.name}!"
    mailer_fn.(user.email, "Welcome", email_content)
  end
end

# 프로덕션
def mailer(to, subject, body) do
  Swoosh.Email.new()
  |> Swoosh.Email.to(to)
  |> Swoosh.Email.subject(subject)
  |> Swoosh.Email.text_body(body)
  |> Mailer.deliver()
end

EmailService.send_welcome(&mailer/3, user)

# 테스트
test "sends email" do
  sent_emails = []

  mock_mailer = fn to, subject, body ->
    {:ok, %{to: to, subject: subject}}
  end

  {:ok, email} = EmailService.send_welcome(mock_mailer, user)
  assert email.to == user.email
end
```

## 설정 기반 주입

```elixir
# config/config.exs
config :myapp, Myapp.Storage,
  adapter: Myapp.Storage.S3,
  bucket: "myapp-bucket",
  region: "us-east-1"

# 또는 테스트 환경
config :myapp, Myapp.Storage,
  adapter: Myapp.Storage.Memory

# lib/myapp/storage.ex
defmodule Myapp.Storage do
  def upload(file) do
    adapter = Application.get_env(:myapp, __MODULE__)[:adapter]
    adapter.upload(file)
  end

  def download(key) do
    adapter = Application.get_env(:myapp, __MODULE__)[:adapter]
    adapter.download(key)
  end
end

# lib/myapp/storage/s3.ex
defmodule Myapp.Storage.S3 do
  def upload(file) do
    # S3에 업로드
    {:ok, "s3-key"}
  end

  def download(key) do
    # S3에서 다운로드
    {:ok, file_content}
  end
end

# lib/myapp/storage/memory.ex
defmodule Myapp.Storage.Memory do
  def upload(file) do
    # 메모리에 저장
    {:ok, "memory-key"}
  end

  def download(key) do
    # 메모리에서 조회
    {:ok, "file-content"}
  end
end
```

## 모듈 주입

```elixir
defmodule PaymentProcessor do
  def process_payment(amount, payment_module \\ Stripe) do
    payment_module.charge(amount)
  end
end

# 실제 구현
defmodule Stripe do
  def charge(amount) do
    # Stripe API 호출
    {:ok, %{id: "charge_123"}}
  end
end

# 테스트
defmodule MockPaymentGateway do
  def charge(_amount) do
    {:ok, %{id: "test_charge"}}
  end
end

test "processes payment" do
  {:ok, charge} = PaymentProcessor.process_payment(100, MockPaymentGateway)
  assert charge.id == "test_charge"
end
```

## GenServer를 이용한 주입

```elixir
defmodule Myapp.CacheManager do
  use GenServer

  def start_link(cache_impl) do
    GenServer.start_link(__MODULE__, cache_impl, name: __MODULE__)
  end

  def init(cache_impl) do
    {:ok, %{cache: cache_impl, data: %{}}}
  end

  def get(key) do
    GenServer.call(__MODULE__, {:get, key})
  end

  def put(key, value) do
    GenServer.cast(__MODULE__, {:put, key, value})
  end

  def handle_call({:get, key}, _from, state) do
    value = state.cache.get(state.data, key)
    {:reply, value, state}
  end

  def handle_cast({:put, key, value}, state) do
    new_data = state.cache.put(state.data, key, value)
    {:noreply, %{state | data: new_data}}
  end
end

# 테스트에서
{:ok, _} = Myapp.CacheManager.start_link(MockCache)
```

## 컨텍스트 기반 주입

```elixir
defmodule UserContext do
  def create_user(attrs, context \\ %{}) do
    repo = context[:repo] || Myapp.Repo
    mailer = context[:mailer] || Myapp.Mailer
    logger = context[:logger] || Logger

    with {:ok, user} <- repo.insert(User.changeset(%User{}, attrs)) do
      logger.info("User created: #{user.id}")
      mailer.send_welcome_email(user)
      {:ok, user}
    else
      {:error, changeset} -> {:error, changeset}
    end
  end
end

# 테스트
test "creates user and sends email" do
  mock_context = %{
    repo: MockRepo,
    mailer: MockMailer,
    logger: MockLogger
  }

  {:ok, user} = UserContext.create_user(%{email: "test@example.com"}, mock_context)
  assert user.id == 1
  assert MockMailer.emails_sent > 0
end
```

## 결론

의존성 주입은 코드의 유연성과 테스트 가능성을 높입니다. Elixir의 다양한 패턴을 활용하여 느슨한 결합의 아키텍처를 만들 수 있습니다.