---
title: "API 레이트 제한 구현"
author: "송태양"
tags: ["api", "security", "performance"]
thumbnail: "/images/thumbnails/rate-limiting.jpg"
summary: "API의 과부하를 방지하고 공정한 자원 사용을 보장하는 레이트 제한을 구현합니다."
published_at: 2024-07-01T09:45:00Z
is_popular: false
---

레이트 제한은 API를 악의적인 사용으로부터 보호합니다. 효과적인 레이트 제한을 구현해봅시다.

## 기본 레이트 제한

```elixir
# lib/myapp/rate_limiter.ex
defmodule Myapp.RateLimiter do
  @window_size 60  # 60초

  def check_rate_limit(identifier, limit \\ 100) do
    key = "rate_limit:#{identifier}"
    current_time = System.system_time(:second)
    window_start = current_time - @window_size

    case Cachex.get(:rate_limit_cache, key) do
      {:ok, nil} ->
        # 첫 요청
        Cachex.put(:rate_limit_cache, key, [current_time], ttl: @window_size)
        {:ok, limit - 1}

      {:ok, timestamps} ->
        # 윈도우 내의 요청만 카운트
        recent_requests = Enum.filter(timestamps, &(&1 > window_start))
        request_count = length(recent_requests)

        if request_count >= limit do
          {:error, "Rate limit exceeded"}
        else
          new_timestamps = [current_time | recent_requests]
          Cachex.put(:rate_limit_cache, key, new_timestamps, ttl: @window_size)
          {:ok, limit - request_count - 1}
        end
    end
  end
end
```

## Token Bucket 알고리즘

```elixir
defmodule TokenBucket do
  @capacity 100
  @refill_rate 10  # 초당 10개 토큰 충전

  def init(identifier) do
    Agent.start_link(
      fn ->
        %{
          identifier: identifier,
          tokens: @capacity,
          last_update: System.monotonic_time()
        }
      end,
      name: String.to_atom("bucket:#{identifier}")
    )
  end

  def consume(identifier, tokens \\ 1) do
    case Agent.get_and_update(String.to_atom("bucket:#{identifier}"), fn state ->
      now = System.monotonic_time()
      elapsed = (now - state.last_update) / 1_000_000_000

      refilled = state.tokens + elapsed * @refill_rate
      current_tokens = min(refilled, @capacity)

      if current_tokens >= tokens do
        {:ok, %{state | tokens: current_tokens - tokens, last_update: now}}
      else
        {{:error, "Insufficient tokens"}, state}
      end
    end) do
      {:ok, state} -> {:ok, state}
      error -> error
    end
  end
end
```

## 플러그 기반 구현

```elixir
# lib/myapp_web/plugs/rate_limit.ex
defmodule MyappWeb.Plugs.RateLimit do
  import Plug.Conn

  @default_limit 100
  @default_window 60

  def init(options) do
    options
  end

  def call(conn, opts) do
    limit = Keyword.get(opts, :limit, @default_limit)
    window = Keyword.get(opts, :window, @default_window)

    identifier = get_identifier(conn)

    case Myapp.RateLimiter.check_rate_limit(identifier, limit, window) do
      {:ok, remaining} ->
        conn
        |> put_resp_header("x-ratelimit-limit", to_string(limit))
        |> put_resp_header("x-ratelimit-remaining", to_string(remaining))
        |> put_resp_header("x-ratelimit-reset", to_string(get_reset_time(window)))

      {:error, _} ->
        conn
        |> put_status(429)
        |> put_resp_header("retry-after", to_string(window))
        |> json(%{error: "Rate limit exceeded"})
        |> halt()
    end
  end

  defp get_identifier(conn) do
    # IP 주소 또는 사용자 ID
    case get_session(conn, :user_id) do
      nil -> get_client_ip(conn)
      user_id -> "user:#{user_id}"
    end
  end

  defp get_client_ip(conn) do
    conn.remote_ip
    |> Tuple.to_list()
    |> Enum.join(".")
  end

  defp get_reset_time(window) do
    System.system_time(:second) + window
  end
end
```

## 라우터에서 사용

```elixir
defmodule MyappWeb.Router do
  use MyappWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
    plug MyappWeb.Plugs.RateLimit, limit: 100, window: 60
  end

  pipeline :public_api do
    plug :accepts, ["json"]
    plug MyappWeb.Plugs.RateLimit, limit: 10, window: 60
  end

  scope "/api/v1", MyappWeb.API.V1 do
    pipe_through :api

    resources :posts, PostController
  end

  scope "/api/v1/public", MyappWeb.API.V1 do
    pipe_through :public_api

    get "/stats", StatsController, :index
  end
end
```

## 계층 기반 제한

```elixir
defmodule TieredRateLimit do
  @limits %{
    free: %{requests: 100, window: 3600},
    pro: %{requests: 10000, window: 3600},
    enterprise: %{requests: :unlimited, window: 3600}
  }

  def get_limit(user) do
    tier = user.subscription_tier || :free
    Map.get(@limits, tier)
  end

  def check_limit(user, identifier) do
    %{requests: limit, window: window} = get_limit(user)

    if limit == :unlimited do
      {:ok, :unlimited}
    else
      Myapp.RateLimiter.check_rate_limit(identifier, limit, window)
    end
  end
end
```

## 결론

효과적한 레이트 제한은 API의 안정성을 보장하고 악의적인 사용을 방지합니다. 사용 계층, 엔드포인트 특성에 따라 다양한 제한을 설정할 수 있습니다.