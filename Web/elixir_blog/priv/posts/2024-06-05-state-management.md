---
title: "Phoenix 상태 관리 패턴"
author: "최지훈"
tags: ["phoenix", "state-management", "programming"]
thumbnail: "/images/thumbnails/state-management.jpg"
summary: "GenServer와 Agent를 이용한 상태 관리 기법을 배웁니다."
published_at: 2024-06-05T13:45:00Z
is_popular: true
---

상태 관리는 애플리케이션의 복잡도를 줄이는 핵심입니다. Elixir의 상태 관리 패턴을 알아봅시다.

## Agent를 이용한 간단한 상태 관리

```elixir
defmodule AppState do
  def init do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def get(key) do
    Agent.get(__MODULE__, &Map.get(&1, key))
  end

  def set(key, value) do
    Agent.update(__MODULE__, &Map.put(&1, key, value))
  end

  def all do
    Agent.get(__MODULE__, & &1)
  end
end

# 사용
AppState.init()
AppState.set(:user_count, 0)
AppState.get(:user_count)  # 0
```

## GenServer를 이용한 복잡한 상태 관리

```elixir
defmodule SessionManager do
  use GenServer
  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    {:ok, state}
  end

  def create_session(user_id) do
    session_id = UUID.uuid4()
    GenServer.call(__MODULE__, {:create, user_id, session_id})
    session_id
  end

  def get_session(session_id) do
    GenServer.call(__MODULE__, {:get, session_id})
  end

  def delete_session(session_id) do
    GenServer.cast(__MODULE__, {:delete, session_id})
  end

  # 콜백
  def handle_call({:create, user_id, session_id}, _from, state) do
    session = %{
      id: session_id,
      user_id: user_id,
      created_at: DateTime.utc_now()
    }

    new_state = Map.put(state, session_id, session)
    Logger.info("Session created: #{session_id}")
    {:reply, session, new_state}
  end

  def handle_call({:get, session_id}, _from, state) do
    session = Map.get(state, session_id)
    {:reply, session, state}
  end

  def handle_cast({:delete, session_id}, state) do
    Logger.info("Session deleted: #{session_id}")
    {:noreply, Map.delete(state, session_id)}
  end
end
```

## ETS를 이용한 고성능 상태 저장소

```elixir
defmodule CacheStore do
  def init do
    :ets.new(:cache, [:set, :public, :named_table])
  end

  def get(key) do
    case :ets.lookup(:cache, key) do
      [{^key, value}] -> {:ok, value}
      [] -> :error
    end
  end

  def put(key, value, ttl \\ :infinity) do
    expiry = if ttl == :infinity do
      :infinity
    else
      System.monotonic_time(:second) + ttl
    end

    :ets.insert(:cache, {key, value, expiry})
  end

  def cleanup_expired do
    now = System.monotonic_time(:second)

    :ets.match_delete(:cache, {:"_", :"_", {:"<", now}})
  end

  def all_keys do
    :ets.all(:cache)
    |> Enum.map(fn key -> :ets.lookup(:cache, key) end)
  end
end
```

## LiveView의 상태 관리

```elixir
defmodule MyappWeb.CounterLive do
  use MyappWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, count: 0, history: [])}
  end

  def handle_event("increment", _, socket) do
    new_count = socket.assigns.count + 1
    new_history = [new_count | socket.assigns.history]

    {:noreply, assign(socket,
      count: new_count,
      history: Enum.take(new_history, 10)
    )}
  end

  def handle_event("reset", _, socket) do
    {:noreply, assign(socket, count: 0, history: [])}
  end

  def handle_event("undo", _, socket) do
    case socket.assigns.history do
      [prev | rest] ->
        {:noreply, assign(socket,
          count: prev,
          history: rest
        )}
      [] ->
        {:noreply, socket}
    end
  end
end
```

## 전역 상태 관리

```elixir
defmodule AppContext do
  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(_state) do
    initial_state = %{
      settings: load_settings(),
      users_online: 0,
      active_sessions: []
    }

    schedule_cleanup()
    {:ok, initial_state}
  end

  def update_setting(key, value) do
    GenServer.cast(__MODULE__, {:update_setting, key, value})
  end

  def get_setting(key) do
    GenServer.call(__MODULE__, {:get_setting, key})
  end

  def increment_online_users do
    GenServer.cast(__MODULE__, :increment_online)
  end

  def handle_cast({:update_setting, key, value}, state) do
    new_settings = Map.put(state.settings, key, value)
    {:noreply, %{state | settings: new_settings}}
  end

  def handle_cast(:increment_online, state) do
    {:noreply, %{state | users_online: state.users_online + 1}}
  end

  def handle_call({:get_setting, key}, _from, state) do
    {:reply, state.settings[key], state}
  end

  def handle_info(:cleanup, state) do
    # 주기적 정리 작업
    schedule_cleanup()
    {:noreply, state}
  end

  defp load_settings do
    # 설정 로드
    %{}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, 60_000)  # 1분마다
  end
end
```

## 상태 동기화

```elixir
defmodule StateSynchronizer do
  def sync_state(source_state, target_state) do
    Map.merge(target_state, source_state)
  end

  def diff(old_state, new_state) do
    new_state
    |> Enum.filter(fn {key, value} ->
      old_state[key] != value
    end)
    |> Enum.into(%{})
  end

  def apply_diff(state, diff) do
    Map.merge(state, diff)
  end
end
```

## 결론

적절한 상태 관리는 애플리케이션의 복잡도를 줄이고 테스트 가능성을 높입니다. 상황에 맞게 Agent, GenServer, ETS 등을 선택하여 효율적인 상태 관리를 구현할 수 있습니다.