---
title: "Elixir/Phoenix 성능 최적화 기법"
author: "윤서연"
tags: ["performance", "elixir", "optimization"]
thumbnail: "/images/thumbnails/performance-optimization.jpg"
summary: "Elixir 애플리케이션의 성능을 향상시키는 실전 기법들을 배웁니다."
published_at: 2024-03-05T10:30:00Z
is_popular: false
---

성능 최적화는 사용자 경험을 향상시키는 핵심 요소입니다. Elixir/Phoenix 애플리케이션을 최적화하는 방법을 알아봅시다.

## 메모리 프로파일링

### Observer를 이용한 모니터링

```elixir
# IEx 세션에서
iex> :observer.start()
```

Observer는 메모리 사용량, 프로세스, ETS 테이블 등을 시각적으로 모니터링할 수 있게 해줍니다.

## 데이터 구조 최적화

### 리스트 vs 맵

```elixir
# 리스트는 순차 접근에 최적화
list = [1, 2, 3, 4, 5]
Enum.map(list, &(&1 * 2))  # 효율적

# 맵은 키 기반 접근에 최적화
map = %{"a" => 1, "b" => 2, "c" => 3}
map["a"]  # O(1) 접근
```

### ETS 테이블 활용

```elixir
defmodule CacheManager do
  def init do
    :ets.new(:cache, [:set, :public, :named_table])
  end

  def get(key) do
    case :ets.lookup(:cache, key) do
      [{^key, value}] -> {:ok, value}
      [] -> :error
    end
  end

  def put(key, value) do
    :ets.insert(:cache, {key, value})
  end
end
```

## 동시성 최적화

### 적절한 프로세스 풀 크기

```elixir
# config/config.exs
config :myapp, MyappWeb.Endpoint,
  # CPU 바운드 작업용 풀 크기
  max_demand: System.schedulers_online() * 2
```

### 적응형 처리

```elixir
defmodule AdaptiveProcessor do
  def process_in_parallel(items, max_workers \\ nil) do
    workers = max_workers || System.schedulers_online()

    items
    |> Stream.chunk_every(div(length(items), workers) + 1)
    |> Enum.map(&Task.async(fn -> Enum.map(&1, &process_item/1) end))
    |> Task.await_many()
    |> Enum.concat()
  end

  defp process_item(item) do
    # 처리 로직
    item
  end
end
```

## 데이터베이스 성능

### 인덱싱 전략

```elixir
defmodule Repo.Migrations.AddIndexes do
  use Ecto.Migration

  def change do
    # 단일 컬럼 인덱스
    create index(:posts, [:status])
    create index(:posts, [:created_at])

    # 복합 인덱스
    create index(:posts, [:user_id, :status])

    # 부분 인덱스
    create index(:posts, [:status], where: "published = true")
  end
end
```

### 배치 처리

```elixir
defmodule BatchProcessor do
  def process_all_users do
    User
    |> Repo.stream(max_rows: 1000)
    |> Stream.each(&process_user/1)
    |> Stream.run()
  end

  defp process_user(user) do
    # 사용자별 처리
    IO.inspect(user)
  end
end
```

## 캐싱 전략

### 다층 캐싱

```elixir
defmodule PostService do
  @cache_ttl 3600  # 1시간

  def get_post(id) do
    # L1: 프로세스 메모리
    case agent_get(id) do
      {:ok, post} -> {:ok, post}
      :error ->
        # L2: ETS
        case ets_get(id) do
          {:ok, post} ->
            agent_put(id, post)
            {:ok, post}
          :error ->
            # L3: 데이터베이스
            case Repo.get(Post, id) do
              nil -> :error
              post ->
                ets_put(id, post)
                {:ok, post}
            end
        end
    end
  end

  defp agent_get(id) do
    Agent.get(__MODULE__, fn state -> Map.get(state, id) end, :error)
  end

  defp ets_get(id) do
    case :ets.lookup(:post_cache, id) do
      [{^id, post}] -> {:ok, post}
      [] -> :error
    end
  end

  defp ets_put(id, post) do
    :ets.insert(:post_cache, {id, post, System.monotonic_time(:second)})
  end
end
```

## 컴파일 최적화

### 빌드 프로파일링

```bash
# 빌드 시간 측정
time mix compile

# 의존성별 컴파일 시간
mix compile --profile=trace
```

## 결론

성능 최적화는 측정과 프로파일링으로부터 시작됩니다. Elixir의 강력한 도구들과 기법들을 활용하여 고성능의 애플리케이션을 만들 수 있습니다.