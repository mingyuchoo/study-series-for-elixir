---
title: "Phoenix 애플리케이션 Docker 배포 완벽 가이드"
author: "강민지"
tags: ["docker", "devops", "deployment"]
thumbnail: "/images/thumbnails/docker-deployment.jpg"
summary: "Phoenix 애플리케이션을 Docker로 컨테이너화하고 배포하는 방법을 배웁니다."
published_at: 2024-03-01T13:20:00Z
is_popular: true
---

Docker를 이용한 배포는 현대 웹 개발의 필수 기술입니다. Phoenix 애플리케이션을 Docker로 배포하는 방법을 알아봅시다.

## Dockerfile 작성

### 멀티 스테이지 빌드

```dockerfile
# Stage 1: Build
FROM elixir:1.14-alpine as builder

WORKDIR /app

RUN apk add --no-cache git build-base nodejs npm

COPY mix.exs mix.lock ./
RUN mix local.hex --force && mix local.rebar --force
RUN mix deps.get

COPY . .

RUN mix assets.deploy
RUN mix phx.digest
RUN mix release

# Stage 2: Runtime
FROM alpine:latest

RUN apk add --no-cache openssl ncurses-libs

WORKDIR /app

COPY --from=builder /app/_build/prod/rel/myapp ./

ENV HOME=/app PORT=4000
EXPOSE 4000

CMD ["bin/myapp", "start"]
```

이 방식은 빌드 환경과 런타임 환경을 분리하여 최종 이미지 크기를 크게 줄입니다.

## 환경 변수 설정

### 실행 시 환경 변수 전달

```bash
docker run -e DATABASE_URL="postgres://user:pass@db:5432/myapp" \
           -e SECRET_KEY_BASE="your-secret" \
           -p 4000:4000 \
           myapp:latest
```

### docker-compose.yml로 관리

```yaml
version: '3.8'

services:
  db:
    image: postgres:15-alpine
    environment:
      POSTGRES_DB: myapp_dev
      POSTGRES_PASSWORD: postgres
    ports:
      - "5432:5432"
    volumes:
      - db_data:/var/lib/postgresql/data

  web:
    build: .
    ports:
      - "4000:4000"
    environment:
      DATABASE_URL: "postgres://postgres:postgres@db:5432/myapp_dev"
      SECRET_KEY_BASE: "dev-secret-key"
      MIX_ENV: "dev"
    depends_on:
      - db
    volumes:
      - .:/app
    command: mix phx.server

volumes:
  db_data:
```

## 이미지 최적화

### .dockerignore 작성

```
.git
.gitignore
README.md
mix.lock
_build/
deps/
doc/
test/
.elixir_ls/
node_modules/
```

불필요한 파일들을 제외하여 빌드 시간을 단축합니다.

### 캐싱 최적화

```dockerfile
FROM elixir:1.14-alpine

WORKDIR /app

# 의존성 레이어 (자주 변경되지 않음)
COPY mix.exs mix.lock ./
RUN mix local.hex --force && \
    mix deps.get && \
    mix deps.compile

# 소스 코드 레이어 (자주 변경됨)
COPY . .

RUN mix compile
```

변경 빈도가 낮은 레이어부터 정렬하면 Docker 캐시를 효율적으로 활용할 수 있습니다.

## 배포 전략

### Blue-Green 배포

```bash
#!/bin/bash

# Blue 환경 실행
docker run -d --name myapp-blue \
  -p 4000:4000 \
  myapp:v1.0

# 헬스 체크
sleep 5
curl http://localhost:4000/health

# Green 환경 시작
docker run -d --name myapp-green \
  -p 4001:4000 \
  myapp:v2.0

# 스위칭
docker network connect bridge myapp-green
docker stop myapp-blue
docker rename myapp-green myapp-blue
```

### 헬스 체크 구현

```elixir
# lib/myapp_web/controllers/health_controller.ex
defmodule MyappWeb.HealthController do
  use MyappWeb, :controller

  def check(conn, _params) do
    case check_database() do
      :ok ->
        json(conn, %{status: "healthy"})
      :error ->
        conn
        |> put_status(503)
        |> json(%{status: "unhealthy"})
    end
  end

  defp check_database do
    case Ecto.Adapters.SQL.query(Repo, "SELECT 1") do
      {:ok, _} -> :ok
      {:error, _} -> :error
    end
  end
end
```

## 보안 고려사항

### 최소 권한 실행

```dockerfile
# 특정 사용자로 실행
RUN addgroup -S appuser && adduser -S appuser -G appuser
USER appuser

CMD ["bin/myapp", "start"]
```

### 환경 변수 보안

```bash
# 민감한 정보는 Docker secrets 사용
echo "secret-key" | docker secret create db_password -

# Compose에서 사용
docker secret create db_password ./secrets/db_password
```

## 결론

Docker를 이용한 Phoenix 애플리케이션 배포는 일관된 개발-프로덕션 환경을 보장합니다. 멀티 스테이지 빌드, 효율적인 캐싱, 올바른 배포 전략을 통해 안정적이고 확장 가능한 배포를 실현할 수 있습니다.