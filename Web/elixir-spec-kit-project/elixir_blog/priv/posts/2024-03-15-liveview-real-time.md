---
title: "Phoenix LiveView로 실시간 기능 구현하기"
author: "한예진"
tags: ["liveview", "phoenix", "web-dev"]
thumbnail: "/images/thumbnails/liveview-real-time.jpg"
summary: "Phoenix LiveView의 실시간 통신 기능을 이용하여 반응형 웹 애플리케이션을 만듭니다."
published_at: 2024-03-15T11:00:00Z
is_popular: true
---

Phoenix LiveView는 WebSocket을 기반으로 실시간 기능을 제공합니다. 실제 프로젝트에서 사용할 수 있는 실시간 기능들을 알아봅시다.

## LiveView 기본 구조

### 간단한 카운터 예제

```elixir
# lib/myapp_web/live/counter_live.ex
defmodule MyappWeb.CounterLive do
  use MyappWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, count: 0)}
  end

  def render(assigns) do
    ~H"""
    <div>
      <h1>Count: <%= @count %></h1>
      <button phx-click="inc">+</button>
      <button phx-click="dec">-</button>
    </div>
    """
  end

  def handle_event("inc", _value, socket) do
    {:noreply, assign(socket, count: socket.assigns.count + 1)}
  end

  def handle_event("dec", _value, socket) do
    {:noreply, assign(socket, count: socket.assigns.count - 1)}
  end
end
```

## 실시간 데이터 업데이트

### PubSub를 이용한 브로드캐스팅

```elixir
# lib/myapp_web/live/chat_live.ex
defmodule MyappWeb.ChatLive do
  use MyappWeb, :live_view

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Myapp.PubSub, "chat:lobby")
    end

    {:ok, assign(socket, messages: [])}
  end

  def render(assigns) do
    ~H"""
    <div id="chat">
      <div id="messages">
        <%= for msg <- @messages do %>
          <p><strong><%= msg.user %>:</strong> <%= msg.text %></p>
        <% end %>
      </div>

      <form phx-submit="send_message">
        <input type="text" name="message" placeholder="Message...">
        <button type="submit">Send</button>
      </form>
    </div>
    """
  end

  def handle_event("send_message", %{"message" => message}, socket) do
    msg = %{user: socket.assigns.current_user.name, text: message}

    Phoenix.PubSub.broadcast(
      Myapp.PubSub,
      "chat:lobby",
      {:message_created, msg}
    )

    {:noreply, socket}
  end

  def handle_info({:message_created, msg}, socket) do
    {:noreply, assign(socket, messages: socket.assigns.messages ++ [msg])}
  end
end
```

## 폼 입력 처리

### 실시간 폼 검증

```elixir
defmodule MyappWeb.PostFormLive do
  use MyappWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, changeset: Post.changeset(%Post{}))}
  end

  def render(assigns) do
    ~H"""
    <form phx-change="validate" phx-submit="save">
      <input type="text" name="post[title]"
             phx-debounce="500"
             placeholder="Title">
      <%= for {field, error} <- @changeset.errors do %>
        <p class="error"><%= field %>: <%= error %></p>
      <% end %>

      <textarea name="post[content]" placeholder="Content"></textarea>

      <button type="submit">Save</button>
    </form>
    """
  end

  def handle_event("validate", %{"post" => params}, socket) do
    changeset = Post.changeset(%Post{}, params)
    {:noreply, assign(socket, changeset: changeset)}
  end

  def handle_event("save", %{"post" => params}, socket) do
    case Repo.insert(Post.changeset(%Post{}, params)) do
      {:ok, _post} ->
        {:noreply, put_flash(socket, :info, "Post saved")}
      {:error, changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end
end
```

## 성능 최적화

### 변경 감지

```elixir
def handle_info({:post_updated, post}, socket) do
  # 기존 목록에서 게시물 업데이트
  posts = socket.assigns.posts
    |> Enum.map(fn p -> if p.id == post.id, do: post, else: p end)

  {:noreply, assign(socket, posts: posts)}
end
```

### 로드 밸런싱

```elixir
# config/config.exs
config :myapp, MyappWeb.Endpoint,
  pubsub_server: Myapp.PubSub

config :myapp, Myapp.PubSub,
  name: Myapp.PubSub,
  adapter: Phoenix.PubSub.PG2
```

## 고급 기능

### 파일 업로드 진행률

```elixir
def render(assigns) do
  ~H"""
  <form phx-change="upload" id="upload-form">
    <input type="file" name="file" accept="image/*">

    <%= if @upload_progress do %>
      <progress max="100" value={@upload_progress}></progress>
      <p><%= @upload_progress %>%</p>
    <% end %>
  </form>
  """
end

def handle_event("upload", _params, socket) do
  progress = 50  # 실제로는 파일 업로드 진행률 계산

  {:noreply, assign(socket, upload_progress: progress)}
end
```

### 자동 업데이트

```elixir
def mount(_params, _session, socket) do
  if connected?(socket) do
    Process.send_after(self(), :update, 5000)
  end

  {:ok, assign(socket, data: fetch_data())}
end

def handle_info(:update, socket) do
  Process.send_after(self(), :update, 5000)
  {:noreply, assign(socket, data: fetch_data())}
end
```

## 결론

Phoenix LiveView는 웹소켓 기반의 실시간 기능을 간단하게 구현할 수 있게 해줍니다. PubSub, 폼 처리, 성능 최적화 등의 기능을 활용하면 매우 반응형의 사용자 경험을 제공할 수 있습니다.