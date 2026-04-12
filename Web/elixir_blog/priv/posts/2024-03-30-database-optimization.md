---
title: "PostgreSQL 데이터베이스 최적화 가이드"
author: "이영희"
tags: ["database", "performance", "elixir"]
thumbnail: "/images/thumbnails/database-optimization.jpg"
summary: "PostgreSQL 쿼리 최적화, 인덱싱, 실행 계획 분석을 통한 성능 향상 방법을 배웁니다."
published_at: 2024-03-30T10:15:00Z
is_popular: false
---

데이터베이스 성능은 애플리케이션의 전체 성능을 결정합니다. PostgreSQL 최적화 기법을 알아봅시다.

## 실행 계획 분석

### EXPLAIN 명령어

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.id, p.title, a.name
FROM posts p
JOIN authors a ON p.author_id = a.id
WHERE p.published = true;
```

실행 계획을 분석하여 병목 지점을 찾을 수 있습니다.

```elixir
# Elixir에서 실행 계획 확인
Ecto.Adapters.SQL.explain(Repo, :all, from(p in Post, where: p.published == true))
```

## 인덱싱 전략

### 단일 컬럼 인덱스

```elixir
defmodule Repo.Migrations.CreatePostsIndex do
  use Ecto.Migration

  def change do
    # 자주 검색되는 컬럼
    create index(:posts, [:status])
    create index(:posts, [:user_id])
    create index(:posts, [:created_at])
  end
end
```

### 복합 인덱스

```elixir
def change do
  # 자주 함께 사용되는 컬럼들
  create index(:posts, [:user_id, :status, :created_at])
end
```

### 부분 인덱스

```elixir
def change do
  # 활성 게시물만 인덱싱
  create index(:posts, [:user_id],
    where: "status = 'published'",
    name: "posts_published_idx"
  )
end
```

## 쿼리 최적화

### N+1 쿼리 문제 해결

```elixir
# 나쁜 예
posts = Repo.all(Post)
Enum.map(posts, fn post -> post.author.name end)

# 좋은 예
posts = Repo.all(Post) |> Repo.preload(:author)
Enum.map(posts, fn post -> post.author.name end)

# 깊은 관계 프리로드
posts = Repo.all(Post) |> Repo.preload(author: [:profile])
```

### 필요한 컬럼만 선택

```elixir
# 나쁜 예
from(p in Post, select: p)

# 좋은 예
from(p in Post, select: {p.id, p.title, p.created_at})
```

## 배치 처리

### 대량 데이터 처리

```elixir
defmodule DataProcessor do
  def process_all_users do
    User
    |> Repo.stream(max_rows: 1000)
    |> Stream.map(&process_user/1)
    |> Stream.run()
  end

  defp process_user(user) do
    # 사용자별 처리
    Repo.update(user)
  end
end
```

### 대량 삽입 최적화

```elixir
# 나쁜 예 - 1000개씩 1000번 쿼리
posts = generate_posts(1000000)
Enum.each(posts, fn post -> Repo.insert(post) end)

# 좋은 예 - 1000개씩 묶음으로 삽입
posts = generate_posts(1000000)
posts
|> Enum.chunk_every(1000)
|> Enum.each(fn chunk -> Repo.insert_all(Post, chunk) end)
```

## 연결 풀 설정

```elixir
# config/config.exs
config :myapp, Myapp.Repo,
  pool_size: System.schedulers_online() * 2,
  queue_target: 50,
  queue_interval: 1000
```

## 테이블 유지보수

### VACUUM과 ANALYZE

```bash
# 데이터베이스 최적화
VACUUM ANALYZE;

# 특정 테이블
VACUUM ANALYZE posts;
```

Elixir에서 스케줄:

```elixir
defmodule MaintenanceScheduler do
  def schedule_maintenance do
    # 매일 자정에 실행
    schedule_daily_at(~T[00:00:00], fn ->
      Ecto.Adapters.SQL.query(Repo, "VACUUM ANALYZE")
    end)
  end
end
```

## 쿼리 캐싱

```elixir
defmodule PostCache do
  @cache_ttl 3600

  def get_popular_posts do
    cache_key = "popular_posts"

    case Cachex.get(:cache, cache_key) do
      {:ok, nil} ->
        posts = from(p in Post,
          where: p.views > 1000,
          order_by: [desc: p.views]
        ) |> Repo.all()

        Cachex.put(:cache, cache_key, posts, ttl: @cache_ttl)
        posts
      {:ok, posts} ->
        posts
    end
  end
end
```

## 슬로우 쿼리 모니터링

```elixir
# config/config.exs
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:user_id, :query_time]

# 슬로우 쿼리 로깅
defmodule LogSlowQueries do
  def log_if_slow(query_time) when query_time > 1000 do
    Logger.warn("Slow query detected: #{query_time}ms")
  end

  def log_if_slow(_), do: :ok
end
```

## 결론

데이터베이스 최적화는 지속적인 모니터링과 분석을 필요로 합니다. 실행 계획을 분석하고, 적절한 인덱싱을 하며, 쿼리를 최적화하면 애플리케이션의 성능을 크게 향상시킬 수 있습니다.