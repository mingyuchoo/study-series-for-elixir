---
title: "이벤트 기반 아키텍처"
author: "윤서연"
tags: ["architecture", "event-driven", "programming"]
thumbnail: "/images/thumbnails/event-driven.jpg"
summary: "이벤트 기반 아키텍처의 설계와 구현 방법을 배웁니다."
published_at: 2024-09-01T10:30:00Z
is_popular: true
---

이벤트 기반 아키텍처는 확장 가능한 시스템을 만드는 핵심 패턴입니다.

## 이벤트 정의

```elixir
defmodule Events do
  defmodule UserCreated do
    defstruct [:user_id, :email, :timestamp]
  end

  defmodule UserUpdated do
    defstruct [:user_id, :changes, :timestamp]
  end

  defmodule PostPublished do
    defstruct [:post_id, :user_id, :timestamp]
  end

  defmodule CommentAdded do
    defstruct [:comment_id, :post_id, :user_id, :timestamp]
  end
end
```

## 이벤트 발행

```elixir
defmodule EventBus do
  def publish(event) do
    Phoenix.PubSub.broadcast(
      Myapp.PubSub,
      "events",
      {:event, event}
    )
  end

  def subscribe do
    Phoenix.PubSub.subscribe(Myapp.PubSub, "events")
  end
end

defmodule UserService do
  def create_user(attrs) do
    case Repo.insert(User.changeset(%User{}, attrs)) do
      {:ok, user} ->
        event = %Events.UserCreated{
          user_id: user.id,
          email: user.email,
          timestamp: DateTime.utc_now()
        }

        EventBus.publish(event)
        {:ok, user}

      {:error, changeset} ->
        {:error, changeset}
    end
  end
end
```

## 이벤트 핸들러

```elixir
defmodule EventHandlers.UserEventHandler do
  def handle_event(%Events.UserCreated{} = event) do
    # 환영 이메일 발송
    send_welcome_email(event)

    # 사용자 통계 업데이트
    update_user_stats(event)

    # 외부 서비스 호출
    notify_external_service(event)
  end

  def handle_event(%Events.UserUpdated{} = event) do
    # 사용자 변경 로깅
    log_user_change(event)
  end

  defp send_welcome_email(event) do
    # 이메일 발송 로직
    :ok
  end

  defp update_user_stats(event) do
    # 통계 업데이트
    :ok
  end

  defp notify_external_service(event) do
    # 외부 API 호출
    :ok
  end

  defp log_user_change(event) do
    # 변경 로깅
    :ok
  end
end

# 이벤트 구독
defmodule EventListener do
  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def init(_) do
    EventBus.subscribe()
    {:ok, %{}}
  end

  def handle_info({:event, event}, state) do
    EventHandlers.UserEventHandler.handle_event(event)
    {:noreply, state}
  end
end
```

## 이벤트 저장소

```elixir
defmodule EventStore do
  def append(event) do
    event_data = %{
      type: event_type(event),
      data: event,
      timestamp: DateTime.utc_now()
    }

    case Repo.insert(EventLog.changeset(%EventLog{}, event_data)) do
      {:ok, log} -> {:ok, log}
      {:error, reason} -> {:error, reason}
    end
  end

  def get_events(after_id \\ 0) do
    from(e in EventLog,
      where: e.id > ^after_id,
      order_by: [asc: e.id]
    ) |> Repo.all()
  end

  def replay_events do
    get_events()
    |> Enum.each(fn log ->
      event = deserialize(log.data)
      EventHandlers.UserEventHandler.handle_event(event)
    end)
  end

  defp event_type(%Events.UserCreated{}), do: "user_created"
  defp event_type(%Events.UserUpdated{}), do: "user_updated"
  defp event_type(%Events.PostPublished{}), do: "post_published"
  defp event_type(%Events.CommentAdded{}), do: "comment_added"

  defp deserialize(data) do
    # 역직렬화
    data
  end
end

defmodule EventLog do
  use Ecto.Schema

  schema "event_logs" do
    field :type, :string
    field :data, :map
    field :timestamp, :utc_datetime

    timestamps()
  end
end
```

## CQRS 패턴

```elixir
defmodule UserProjection do
  def handle_event(%Events.UserCreated{} = event) do
    # 읽기 모델 업데이트
    Repo.insert(%UserSummary{
      user_id: event.user_id,
      email: event.email,
      created_at: event.timestamp
    })
  end

  def handle_event(%Events.UserUpdated{} = event) do
    # 읽기 모델 업데이트
    user_summary = Repo.get!(UserSummary, event.user_id)

    Repo.update(UserSummary.changeset(user_summary, event.changes))
  end
end

# 쿼리는 빠른 읽기 모델에서
defmodule QueryService do
  def get_user(user_id) do
    Repo.get(UserSummary, user_id)
  end

  def list_recent_users(limit \\ 10) do
    from(u in UserSummary,
      order_by: [desc: u.created_at],
      limit: ^limit
    ) |> Repo.all()
  end
end
```

## 결론

이벤트 기반 아키텍처는 시스템 간의 느슨한 결합과 높은 확장성을 제공합니다. 이벤트 발행-구독 패턴과 이벤트 소싱을 통해 복잡한 비즈니스 로직을 관리할 수 있습니다.