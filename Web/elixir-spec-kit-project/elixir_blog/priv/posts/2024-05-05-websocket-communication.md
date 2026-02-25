---
title: "WebSocket을 이용한 실시간 통신"
author: "한예진"
tags: ["websocket", "phoenix", "real-time"]
thumbnail: "/images/thumbnails/websocket-comm.jpg"
summary: "Phoenix의 WebSocket 기능을 활용한 실시간 양방향 통신을 배웁니다."
published_at: 2024-05-05T11:00:00Z
is_popular: true
---

WebSocket은 실시간 양방향 통신을 위한 프로토콜입니다. Phoenix를 이용한 WebSocket 구현을 알아봅시다.

## 채널 기본 구조

```elixir
# lib/myapp_web/channels/room_channel.ex
defmodule MyappWeb.RoomChannel do
  use MyappWeb, :channel

  def join("room:lobby", _message, socket) do
    {:ok, socket}
  end

  def join("room:" <> _private, _params, _socket) do
    {:error, :unauthorized}
  end

  def handle_in("new_message", %{"body" => body}, socket) do
    broadcast(socket, "new_message", %{body: body})
    {:noreply, socket}
  end

  def handle_out("new_message", payload, socket) do
    push(socket, "new_message", payload)
    {:noreply, socket}
  end
end
```

## 라우터 설정

```elixir
# lib/myapp_web/router.ex
defmodule MyappWeb.Router do
  use MyappWeb, :router

  scope "/socket", MyappWeb do
    socket "/socket", MyappWeb.UserSocket,
      websocket: [timeout: 45_000]
  end
end
```

### UserSocket 설정

```elixir
# lib/myapp_web/channels/user_socket.ex
defmodule MyappWeb.UserSocket do
  use Phoenix.Socket

  channel "room:*", MyappWeb.RoomChannel
  channel "user:*", MyappWeb.UserChannel

  def connect(params, socket) do
    case authenticate_user(params) do
      {:ok, user} ->
        {:ok, assign(socket, :user_id, user.id)}
      :error ->
        :error
    end
  end

  def id(socket) do
    "user_socket:#{socket.assigns.user_id}"
  end

  defp authenticate_user(%{"token" => token}) do
    case Myapp.Auth.Token.verify_token(token) do
      {:ok, claims} ->
        {:ok, %{id: claims["user_id"]}}
      {:error, _} ->
        :error
    end
  end

  defp authenticate_user(_), do: :error
end
```

## 클라이언트 구현

```javascript
// assets/js/socket.js
import { Socket } from "phoenix"

let socket = new Socket("/socket", {
  params: { token: window.userToken }
})

socket.connect()

let channel = socket.channel("room:lobby", {})

channel.join()
  .receive("ok", resp => {
    console.log("Joined room", resp)
  })
  .receive("error", resp => {
    console.log("Unable to join", resp)
  })

channel.on("new_message", payload => {
  console.log("New message:", payload.body)
})

let input = document.querySelector("input[data-test='message-input']")
input.addEventListener("keypress", event => {
  if (event.key === "Enter") {
    channel.push("new_message", {body: input.value})
      .receive("ok", () => input.value = "")
  }
})

export default socket
```

## 양방향 통신

```elixir
defmodule MyappWeb.NotificationChannel do
  use MyappWeb, :channel

  def join("user:" <> user_id, _params, socket) do
    if socket.assigns.user_id == String.to_integer(user_id) do
      {:ok, socket}
    else
      {:error, :unauthorized}
    end
  end

  def handle_in("mark_read", %{"notification_id" => id}, socket) do
    notification = Repo.get!(Notification, id)

    case Repo.update(Notification.changeset(notification, %{read: true})) do
      {:ok, _} ->
        broadcast(socket, "notification_marked_read", %{id: id})
        {:noreply, socket}
      {:error, _} ->
        {:reply, {:error, %{reason: "failed"}}, socket}
    end
  end
end
```

## 서버에서 클라이언트로 푸시

```elixir
defmodule MyappWeb.NotificationService do
  def notify_user(user_id, message) do
    # 특정 사용자에게 알림 전송
    Phoenix.PubSub.broadcast(
      Myapp.PubSub,
      "user:#{user_id}",
      {:notification, message}
    )
  end

  def broadcast_to_room(room_id, message) do
    # 특정 채널의 모든 클라이언트에게 브로드캐스트
    Phoenix.PubSub.broadcast(
      Myapp.PubSub,
      "room:#{room_id}",
      {:new_message, message}
    )
  end
end

# 채널에서 구독
def join("user:" <> user_id, _params, socket) do
  Phoenix.PubSub.subscribe(Myapp.PubSub, "user:#{user_id}")
  {:ok, socket}
end

def handle_info({:notification, message}, socket) do
  push(socket, "notification", message)
  {:noreply, socket}
end
```

## 성능 최적화

```elixir
defmodule MyappWeb.PresenceChannel do
  use MyappWeb, :channel

  alias Phoenix.Presence

  def join("presence:" <> _topic, _params, socket) do
    send(self(), :after_join)
    {:ok, socket}
  end

  def handle_info(:after_join, socket) do
    {:ok, _} = Presence.track(socket, socket.assigns.user_id, %{
      online_at: inspect(System.system_time(:second))
    })
    {:noreply, socket}
  end

  def handle_metas({:sync, _old, _new}, _socket) do
    :ok
  end

  def handle_metas({:join, user_id, meta}, socket) do
    push(socket, "user_joined", %{user_id: user_id, meta: meta})
    {:noreply, socket}
  end

  def handle_metas({:leave, user_id, _meta}, socket) do
    push(socket, "user_left", %{user_id: user_id})
    {:noreply, socket}
  end
end
```

## 결론

Phoenix의 강력한 WebSocket 지원을 통해 실시간 양방향 통신을 쉽게 구현할 수 있습니다. 채널, PubSub, Presence를 활용하면 스케일 가능한 실시간 애플리케이션을 만들 수 있습니다.