---
title: "웹 애플리케이션 캐싱 전략"
author: "최지훈"
tags: ["caching", "performance", "architecture"]
thumbnail: "/images/thumbnails/caching-strategies.jpg"
summary: "Redis, ETS, 그리고 애플리케이션 레벨의 다양한 캐싱 전략을 배웁니다."
published_at: 2024-04-15T13:45:00Z
is_popular: true
---

캐싱은 성능 최적화의 핵심입니다. 효과적인 캐싱 전략을 알아봅시다.

## 캐싱 레이어

### L1: 프로세스 메모리

```elixir
defmodule ProcessCache do
  def init do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def get(key, default \\ nil) do
    Agent.get(__MODULE__, fn state ->
      Map.get(state, key, default)
    end)
  end

  def put(key, value) do
    Agent.update(__MODULE__, fn state ->
      Map.put(state, key, value)
    end)
  end

  def delete(key) do
    Agent.update(__MODULE__, fn state ->
      Map.delete(state, key)
    end)
  end
end
```

### L2: ETS (Erlang Term Storage)

```elixir
defmodule ETSCache do
  def init do
    :ets.new(:app_cache, [:set, :public, :named_table,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ])
  end

  def get(key) do
    case :ets.lookup(:app_cache, key) do
      [{^key, value, ttl}] ->
        if expired?(ttl) do
          :ets.delete(:app_cache, key)
          :error
        else
          {:ok, value}
        end
      [] -> :error
    end
  end

  def put(key, value, ttl_seconds \\ 3600) do
    expiry = System.monotonic_time(:second) + ttl_seconds
    :ets.insert(:app_cache, {key, value, expiry})
  end

  defp expired?(expiry) do
    System.monotonic_time(:second) > expiry
  end
end
```

### L3: Redis

```elixir
defmodule RedisCache do
  def get(key) do
    case Redix.command(:redix, ["GET", key]) do
      {:ok, value} when not is_nil(value) ->
        {:ok, Jason.decode!(value)}
      {:ok, nil} ->
        :error
      {:error, reason} ->
        {:error, reason}
    end
  end

  def put(key, value, ttl_seconds \\ 3600) do
    Redix.command(:redix, ["SETEX", key, ttl_seconds, Jason.encode!(value)])
  end

  def delete(key) do
    Redix.command(:redix, ["DEL", key])
  end

  def invalidate_pattern(pattern) do
    Redix.command(:redix, ["EVAL", delete_script(), 0, pattern])
  end

  defp delete_script do
    """
    local keys = redis.call('KEYS', ARGV[1])
    for i=1,#keys do
      redis.call('DEL', keys[i])
    end
    return #keys
    """
  end
end
```

## 캐시 워밍 (Cache Warming)

```elixir
defmodule CacheWarmer do
  def warm_cache do
    warm_popular_posts()
    warm_categories()
    warm_tags()
  end

  defp warm_popular_posts do
    posts = from(p in Post,
      where: p.views > 1000,
      order_by: [desc: p.views],
      limit: 100
    ) |> Repo.all()

    Enum.each(posts, fn post ->
      RedisCache.put("post:#{post.id}", post, 7200)
    end)
  end

  defp warm_categories do
    categories = Repo.all(Category)
    Enum.each(categories, fn cat ->
      RedisCache.put("category:#{cat.id}", cat, 86400)
    end)
  end

  defp warm_tags do
    tags = Repo.all(Tag)
    Enum.each(tags, fn tag ->
      RedisCache.put("tag:#{tag.id}", tag, 86400)
    end)
  end
end
```

## 캐시 무효화 전략

### TTL 기반

```elixir
defmodule TTLCache do
  @default_ttl 3600

  def get_with_ttl(key, func, ttl \\ @default_ttl) do
    case RedisCache.get(key) do
      {:ok, value} -> {:ok, value}
      :error ->
        value = func.()
        RedisCache.put(key, value, ttl)
        {:ok, value}
    end
  end
end
```

### 이벤트 기반 무효화

```elixir
defmodule CacheInvalidator do
  def on_post_update(post) do
    # 게시물 자체 캐시 삭제
    RedisCache.delete("post:#{post.id}")

    # 관련 캐시 삭제
    RedisCache.invalidate_pattern("post:#{post.category_id}:*")
    RedisCache.invalidate_pattern("user:#{post.user_id}:posts:*")

    # 전체 목록 캐시 삭제
    RedisCache.delete("posts:list")

    # 이벤트 발행
    Phoenix.PubSub.broadcast(Myapp.PubSub, "cache", {:post_updated, post})
  end

  def on_post_delete(post_id) do
    RedisCache.delete("post:#{post_id}")
    RedisCache.invalidate_pattern("user:*:posts:*")
    RedisCache.delete("posts:list")
  end
end
```

## 캐시 일관성

### Write-Through 패턴

```elixir
defmodule WriteThrough do
  def update_post(post_id, attrs) do
    with {:ok, post} <- Repo.get_and_update(Post, post_id, attrs),
         :ok <- RedisCache.put("post:#{post_id}", post) do
      {:ok, post}
    else
      {:error, reason} -> {:error, reason}
    end
  end
end
```

### Write-Behind 패턴

```elixir
defmodule WriteBehind do
  def update_post_async(post_id, attrs) do
    # 캐시에 먼저 업데이트
    RedisCache.put("post:#{post_id}", attrs)

    # 비동기로 데이터베이스 업데이트
    Task.Supervisor.start_child(TaskSupervisor, fn ->
      Repo.get_and_update(Post, post_id, attrs)
    end)

    {:ok, "Update in progress"}
  end
end
```

## 캐시 통계 및 모니터링

```elixir
defmodule CacheStats do
  def init do
    Agent.start_link(fn -> %{hits: 0, misses: 0} end, name: __MODULE__)
  end

  def record_hit do
    Agent.update(__MODULE__, fn state ->
      Map.update(state, :hits, 1, &(&1 + 1))
    end)
  end

  def record_miss do
    Agent.update(__MODULE__, fn state ->
      Map.update(state, :misses, 1, &(&1 + 1))
    end)
  end

  def hit_rate do
    Agent.get(__MODULE__, fn state ->
      total = state.hits + state.misses
      if total == 0, do: 0, else: state.hits / total * 100
    end)
  end

  def stats do
    Agent.get(__MODULE__, fn state -> state end)
  end
end
```

## 결론

효과적한 캐싱은 다층 접근을 필요로 합니다. 프로세스 메모리, ETS, Redis를 적절히 조합하고, 캐시 무효화 전략을 잘 수립하면 애플리케이션의 성능을 크게 향상시킬 수 있습니다.