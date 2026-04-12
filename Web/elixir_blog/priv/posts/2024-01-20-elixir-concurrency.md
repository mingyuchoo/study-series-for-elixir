---
title: "Elixir의 동시성 프로그래밍"
author: "이영희"
tags: ["elixir", "concurrency", "programming"]
thumbnail: "/images/thumbnails/elixir-concurrency.jpg"
summary: "Elixir의 강력한 동시성 모델을 이해하고 실전에서 활용하는 방법을 배웁니다."
published_at: 2024-01-20T10:00:00Z
is_popular: true
---

# Elixir의 동시성 프로그래밍

Elixir는 Erlang VM 위에서 동작하며, 수십 년간 검증된 동시성 모델을 제공합니다.

## Actor 모델

Elixir의 동시성은 Actor 모델을 기반으로 합니다. 각 프로세스는 독립적으로 실행되며 메시지를 통해서만 통신합니다.

### 프로세스 생성

```elixir
pid = spawn(fn ->
  IO.puts("안녕하세요!")
end)
```

## GenServer

GenServer는 Elixir에서 가장 많이 사용되는 동시성 추상화입니다.

```elixir
defmodule Counter do
  use GenServer

  def start_link(initial_value) do
    GenServer.start_link(__MODULE__, initial_value, name: __MODULE__)
  end

  def init(initial_value) do
    {:ok, initial_value}
  end

  def handle_call(:get, _from, state) do
    {:reply, state, state}
  end
end
```

## Supervision Trees

프로세스 감독 트리를 통해 장애 복구를 자동화할 수 있습니다.

### Supervisor 설정

```elixir
defmodule MyApp.Supervisor do
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, :ok, opts)
  end

  def init(:ok) do
    children = [
      {Counter, 0},
      {MyApp.Worker, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
```

## Task와 비동기 처리

간단한 비동기 작업은 Task 모듈을 사용합니다.

```elixir
task = Task.async(fn ->
  # 긴 작업
  :timer.sleep(1000)
  "완료!"
end)

result = Task.await(task)
```

## 결론

Elixir의 동시성 모델은 확장 가능하고 장애에 강한 시스템을 구축하는 데 이상적입니다. 프로세스의 격리와 메시지 패싱을 통해 예측 가능하고 안전한 동시성 프로그래밍이 가능합니다.
