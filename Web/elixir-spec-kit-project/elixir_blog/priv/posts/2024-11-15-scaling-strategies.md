---
title: "애플리케이션 확장 전략"
author: "이영희"
tags: ["scaling", "architecture", "performance"]
thumbnail: "/images/thumbnails/scaling-strategies.jpg"
summary: "수평 확장과 수직 확장을 통한 애플리케이션 성장 전략을 배웁니다."
published_at: 2024-11-15T14:20:00Z
is_popular: false
---

애플리케이션이 성장하면서 확장은 피할 수 없습니다. 효과적인 확장 전략을 알아봅시다.

## 수평 확장 (Horizontal Scaling)

```elixir
# 로드 밸런싱 설정
defmodule LoadBalancer do
  def route_request(request) do
    backend = select_backend()
    forward_to_backend(backend, request)
  end

  defp select_backend do
    # Round-robin 또는 최소 연결 알고리즘
    backends = [
      "app-1:4000",
      "app-2:4000",
      "app-3:4000"
    ]

    Enum.random(backends)
  end

  defp forward_to_backend(backend, request) do
    # HTTP 요청 전달
    :ok
  end
end

# Nginx 설정 예시
# upstream app_backend {
#   server app-1:4000;
#   server app-2:4000;
#   server app-3:4000;
# }
# server {
#   listen 80;
#   location / {
#     proxy_pass http://app_backend;
#   }
# }
```

## 수직 확장 (Vertical Scaling)

```elixir
defmodule VerticalScaling do
  def optimize_memory do
    # 메모리 최적화
    Application.put_env(:myapp, :cache_size, 1000)
  end

  def optimize_connections do
    # 데이터베이스 연결 최적화
    max_connections = System.schedulers_online() * 4

    Application.put_env(:myapp, Myapp.Repo,
      pool_size: max_connections
    )
  end

  def increase_processes do
    # Erlang 프로세스 증가
    :erl_prim_loader.set_path([...])
  end
end
```

## 데이터베이스 확장

```elixir
# Read Replica 설정
defmodule ReadReplica do
  def get_from_replica(query) do
    case Myapp.Repo.ReadReplica.one(query) do
      nil -> Myapp.Repo.one(query)  # 폴백
      result -> result
    end
  end

  def write_to_primary(changeset) do
    # 모든 쓰기는 주 데이터베이스로
    Myapp.Repo.insert_or_update(changeset)
  end
end

# Sharding 예시
defmodule Sharding do
  @num_shards 8

  def get_shard(user_id) do
    rem(user_id, @num_shards)
  end

  def get_repo_for_user(user_id) do
    shard = get_shard(user_id)
    String.to_atom("Elixir.Myapp.Repo.Shard#{shard}")
  end

  def query_all_shards(query_fn) do
    0..(@num_shards - 1)
    |> Enum.map(&query_fn.(&1))
    |> Enum.concat()
  end
end
```

## 캐시 계층 추가

```elixir
defmodule CachingStrategy do
  def get_user(user_id) do
    case Redis.get("user:#{user_id}") do
      {:ok, user} -> user
      {:miss, _} ->
        user = Repo.get(User, user_id)
        Redis.set("user:#{user_id}", user, ex: 3600)
        user
    end
  end

  def invalidate_user(user_id) do
    Redis.del("user:#{user_id}")
  end

  def warming_cache do
    # 캐시 워밍
    users = Repo.all(User)
    Enum.each(users, fn user ->
      Redis.set("user:#{user.id}", user, ex: 3600)
    end)
  end
end
```

## 비동기 처리

```elixir
defmodule AsyncProcessing do
  def process_large_batch(items) do
    items
    |> Enum.chunk_every(100)
    |> Enum.each(fn chunk ->
      Task.Supervisor.start_child(
        TaskSupervisor,
        fn -> process_chunk(chunk) end
      )
    end)
  end

  defp process_chunk(items) do
    Enum.each(items, &process_item/1)
  end

  defp process_item(item) do
    # 처리 로직
    :ok
  end
end
```

## 모니터링 및 메트릭

```elixir
defmodule ScalingMetrics do
  def setup_scaling_metrics do
    :prometheus_gauge.new([
      {:name, :active_connections},
      {:help, "Active database connections"}
    ])

    :prometheus_gauge.new([
      {:name, :queue_length},
      {:help, "Job queue length"}
    ])

    :prometheus_histogram.new([
      {:name, :request_duration_seconds},
      {:help, "Request processing time"},
      {:buckets, [0.1, 0.5, 1.0, 5.0, 10.0]}
    ])
  end

  def scaling_decision do
    with {:ok, cpu_load} <- get_cpu_load(),
         {:ok, memory_usage} <- get_memory_usage(),
         {:ok, queue_length} <- get_queue_length() do
      case {cpu_load, memory_usage, queue_length} do
        {cpu, _, _} when cpu > 80 ->
          {:scale_up, "High CPU"}
        {_, mem, _} when mem > 85 ->
          {:scale_up, "High Memory"}
        {_, _, queue} when queue > 1000 ->
          {:scale_up, "Long Queue"}
        {_, _, _} ->
          {:maintain, "Normal"}
      end
    end
  end

  defp get_cpu_load do
    # CPU 부하 조회
    {:ok, 50}
  end

  defp get_memory_usage do
    # 메모리 사용률 조회
    {:ok, 60}
  end

  defp get_queue_length do
    # 큐 길이 조회
    {:ok, 100}
  end
end
```

## 결론

효과적한 확장은 단계적 접근이 필요합니다. 수직 확장으로 시작하여 성능 병목을 분석한 후, 필요한 영역에서 수평 확장을 진행하면 비용 효율적인 성장을 달성할 수 있습니다.