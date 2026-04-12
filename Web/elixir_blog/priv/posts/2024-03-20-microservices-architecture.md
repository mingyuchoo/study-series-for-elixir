---
title: "Elixir로 마이크로서비스 아키텍처 구축"
author: "송태양"
tags: ["architecture", "programming", "elixir"]
thumbnail: "/images/thumbnails/microservices-architecture.jpg"
summary: "Elixir를 이용한 마이크로서비스 아키텍처 설계와 구현을 배웁니다."
published_at: 2024-03-20T09:30:00Z
is_popular: false
---

마이크로서비스 아키텍처는 큰 애플리케이션을 작은 서비스로 분해합니다. Elixir를 이용하여 이를 구현하는 방법을 알아봅시다.

## 마이크로서비스 기본 개념

### 서비스 분해

```
MyApp
├── User Service
├── Post Service
├── Comment Service
└── Notification Service
```

각 서비스는 독립적으로 배포, 스케일링, 업그레이드될 수 있습니다.

## 서비스 간 통신

### HTTP/REST API

```elixir
# user_service/lib/user_service/client.ex
defmodule UserService.Client do
  @base_url Application.get_env(:user_service, :base_url)

  def get_user(user_id) do
    HTTPoison.get!("#{@base_url}/users/#{user_id}")
    |> handle_response()
  end

  defp handle_response(%HTTPoison.Response{body: body, status_code: 200}) do
    {:ok, Jason.decode!(body)}
  end

  defp handle_response(%HTTPoison.Response{status_code: 404}) do
    {:error, :not_found}
  end
end
```

### RPC를 통한 통신

```elixir
# config/config.exs
config :post_service, PostService,
  user_service_node: :"user_service@localhost"

# lib/post_service.ex
defmodule PostService do
  def get_author(user_id) do
    user_service_node = Application.get_env(:post_service, :user_service_node)

    :rpc.call(user_service_node, UserService, :get_user, [user_id])
  end
end
```

## 서비스 디스커버리

### 정적 설정

```elixir
# config/config.exs
config :myapp, :services,
  user_service: "http://user-service:4001",
  post_service: "http://post-service:4002",
  comment_service: "http://comment-service:4003"
```

### 동적 디스커버리

```elixir
defmodule ServiceRegistry do
  def register_service(name, url) do
    Agent.update(__MODULE__, fn services ->
      Map.put(services, name, url)
    end)
  end

  def get_service(name) do
    Agent.get(__MODULE__, fn services ->
      Map.get(services, name)
    end)
  end
end

# 시작
Agent.start_link(fn -> %{} end, name: ServiceRegistry)

# 사용
ServiceRegistry.register_service(:user_service, "http://localhost:4001")
url = ServiceRegistry.get_service(:user_service)
```

## 데이터 일관성

### 이벤트 기반 통신

```elixir
# post_service/lib/post_service/event_handler.ex
defmodule PostService.EventHandler do
  def handle_event(%{type: "user.created", data: user_data}) do
    # 사용자 데이터 동기화
    PostService.Repo.insert(%{
      user_id: user_data.id,
      user_name: user_data.name
    })
  end

  def handle_event(%{type: "user.deleted", data: user_data}) do
    # 사용자 관련 게시물 처리
    from(p in Post, where: p.user_id == ^user_data.id)
    |> PostService.Repo.delete_all()
  end
end

# 이벤트 발행
def publish_event(type, data) do
  event = %{type: type, data: data, timestamp: DateTime.utc_now()}

  Phoenix.PubSub.broadcast(
    :event_bus,
    "events",
    {:event, event}
  )
end
```

## 분산 트랜잭션

### Saga 패턴

```elixir
defmodule OrderSaga do
  def process_order(order_id) do
    with {:ok, user} <- validate_user(order_id),
         {:ok, inventory} <- reserve_inventory(order_id),
         {:ok, payment} <- process_payment(order_id) do
      {:ok, %{user: user, inventory: inventory, payment: payment}}
    else
      {:error, reason} -> rollback(order_id, reason)
    end
  end

  defp rollback(order_id, _reason) do
    # 이전 단계 롤백
    release_inventory(order_id)
    cancel_payment(order_id)
    {:error, "Order processing failed"}
  end
end
```

## 모니터링 및 로깅

### 분산 추적

```elixir
defmodule DistributedTracer do
  def trace(name, fun) do
    trace_id = generate_trace_id()
    start_time = System.monotonic_time()

    result = fun.()

    duration = System.monotonic_time() - start_time

    log_trace(%{
      trace_id: trace_id,
      name: name,
      duration: duration,
      result: result
    })

    result
  end

  defp generate_trace_id do
    UUID.uuid4()
  end

  defp log_trace(trace_data) do
    Logger.info("Trace: #{inspect(trace_data)}")
  end
end
```

## 결론

Elixir의 강력한 분산 시스템 기능들을 이용하면 확장 가능한 마이크로서비스 아키텍처를 구축할 수 있습니다. 적절한 통신 방식, 데이터 일관성 관리, 모니터링이 성공의 핵심입니다.