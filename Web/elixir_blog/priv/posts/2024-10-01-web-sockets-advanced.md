---
title: "고급 WebSocket 기능과 최적화"
author: "한예진"
tags: ["websocket", "real-time", "performance"]
thumbnail: "/images/thumbnails/websocket-advanced.jpg"
summary: "대규모 실시간 애플리케이션을 위한 고급 WebSocket 기법을 배웁니다."
published_at: 2024-10-01T09:30:00Z
is_popular: true
---

대규모 실시간 시스템에서는 WebSocket 성능이 중요합니다. 고급 최적화 기법을 알아봅시다.

## 채널 압축

```elixir
# lib/myapp_web/channels/optimized_channel.ex
defmodule MyappWeb.OptimizedChannel do
  use MyappWeb, :channel

  def join("room:" <> room_id, _payload, socket) do
    {:ok, assign(socket, room_id: room_id)}
  end

  def handle_in("message", %{"text" => text}, socket) do
    compressed = compress_message(text)

    broadcast(socket, "message", %{
      data: compressed,
      compressed: true
    })

    {:noreply, socket}
  end

  defp compress_message(text) do
    text
    |> :zlib.compress()
    |> Base.encode64()
  end
end

# 클라이언트 측
# const decompressed = pako.inflate(Base64.decode(data));
```

## 메시지 배치

```elixir
defmodule BatchedChannel do
  use MyappWeb, :channel

  def join("batch:" <> _room, _payload, socket) do
    {:ok, assign(socket, messages: [])}
  end

  def handle_in("add_message", %{"text" => text}, socket) do
    new_messages = [text | socket.assigns.messages]

    case length(new_messages) do
      n when n >= 10 ->
        broadcast(socket, "batch", %{messages: Enum.reverse(new_messages)})
        {:noreply, assign(socket, messages: [])}
      _ ->
        {:noreply, assign(socket, messages: new_messages)}
    end
  end

  def handle_info(:flush, socket) do
    if Enum.any?(socket.assigns.messages) do
      broadcast(socket, "batch", %{messages: Enum.reverse(socket.assigns.messages)})
      {:noreply, assign(socket, messages: [])}
    else
      {:noreply, socket}
    end
  end
end
```

## 멀티플렉싱

```elixir
defmodule MultiplexedSocket do
  use Phoenix.Socket

  channel "notifications:*", MyappWeb.NotificationChannel
  channel "chat:*", MyappWeb.ChatChannel
  channel "presence:*", MyappWeb.PresenceChannel
  channel "analytics:*", MyappWeb.AnalyticsChannel

  def connect(%{"token" => token}, socket) do
    case authenticate_token(token) do
      {:ok, user} ->
        {:ok, assign(socket, user_id: user.id)}
      :error ->
        :error
    end
  end

  def id(socket) do
    "user_socket:#{socket.assigns.user_id}"
  end

  defp authenticate_token(token) do
    # 토큰 검증
    {:ok, %{id: 1}}
  end
end
```

## 백프레셔 처리

```elixir
defmodule BackpressureChannel do
  use MyappWeb, :channel

  def join("stream:" <> _room, _payload, socket) do
    {:ok, assign(socket, buffer: [], max_buffer_size: 1000)}
  end

  def handle_in("data", %{"value" => value}, socket) do
    buffer = [value | socket.assigns.buffer]
    new_socket = assign(socket, buffer: buffer)

    case length(buffer) >= socket.assigns.max_buffer_size do
      true ->
        # 백프레셔: 클라이언트에게 throttle 신호 전송
        push(socket, "throttle", %{reason: "buffer_full"})
        {:noreply, new_socket}
      false ->
        {:noreply, new_socket}
    end
  end

  def handle_in("flush", _payload, socket) do
    # 버퍼 비우기
    process_buffer(socket.assigns.buffer)
    {:noreply, assign(socket, buffer: [])}
  end

  defp process_buffer(buffer) do
    # 버퍼 처리 로직
    :ok
  end
end
```

## 로드 밸런싱

```elixir
# config/config.exs
config :myapp, MyappWeb.Endpoint,
  # PG2는 단일 노드, 다중 노드는 다른 어댑터 필요
  pubsub_server: Myapp.PubSub

config :myapp, Myapp.PubSub,
  name: Myapp.PubSub,
  adapter: Phoenix.PubSub.PG2,
  node_name: Node.self(),
  nodes: [
    :"node1@127.0.0.1",
    :"node2@127.0.0.1",
    :"node3@127.0.0.1"
  ]
```

## 모니터링과 메트릭

```elixir
defmodule WebSocketMetrics do
  def setup_metrics do
    # 연결 수
    :prometheus_gauge.new([
      {:name, :websocket_connections},
      {:help, "Active WebSocket connections"}
    ])

    # 메시지 처리량
    :prometheus_counter.new([
      {:name, :websocket_messages_total},
      {:help, "Total WebSocket messages"}
    ])

    # 메시지 레이턴시
    :prometheus_histogram.new([
      {:name, :websocket_message_duration_ms},
      {:help, "WebSocket message processing time"}
    ])
  end

  def record_connection do
    :prometheus_gauge.inc(:websocket_connections)
  end

  def record_disconnection do
    :prometheus_gauge.dec(:websocket_connections)
  end

  def record_message_processed(duration_ms) do
    :prometheus_counter.inc(:websocket_messages_total)
    :prometheus_histogram.observe(:websocket_message_duration_ms, duration_ms)
  end
end
```

## 결론

고급 WebSocket 최적화는 대규모 실시간 애플리케이션을 안정적으로 운영하는 데 필수적입니다. 압축, 배치 처리, 백프레셔 처리 등을 통해 성능과 안정성을 크게 향상시킬 수 있습니다.