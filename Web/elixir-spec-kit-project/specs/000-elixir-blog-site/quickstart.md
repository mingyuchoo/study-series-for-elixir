# 빠른 시작 가이드: Elixir 블로그 사이트

**브랜치**: `001-korean-blog-site` | **날짜**: 2025-12-29
**목적**: 개발을 위해 Elixir 블로그 사이트를 로컬에서 실행하기

## 사전 요구사항

### 필수 소프트웨어

| 소프트웨어 | 버전 | 설치 |
| -------- | ------- | ------------ |
| Elixir | 1.19 | [elixir-lang.org/install.html](https://elixir-lang.org/install.html) |
| Erlang/OTP | 26+ | Elixir와 함께 설치됨 |
| Node.js | 18+ | [nodejs.org](https://nodejs.org/) (자산 컴파일용) |
| SQLite | 3.x | 대부분 시스템에 사전 설치됨 |
| Docker | 최신 | [docker.com](https://www.docker.com/) (선택사항) |
| Docker Compose | 최신 | Docker Desktop에 포함됨 |

### 설치 확인

```bash
# Elixir 버전 확인
elixir --version
# 예상: Elixir 1.19 (compiled with Erlang/OTP 26)

# Node.js 버전 확인
node --version
# 예상: v18.x 이상

# SQLite 버전 확인
sqlite3 --version
# 예상: 3.x

# Docker 확인 (선택사항)
docker --version
docker-compose --version
```

---

## 빠른 시작 (로컬 개발)

### 1. 새 Phoenix 프로젝트 생성

```bash
# Phoenix 프레임워크 설치
mix archive.install hex phx_new

# LiveView와 함께 새 Phoenix 프로젝트 생성
mix phx.new korean_blog --live --database sqlite3

# 프로젝트 디렉토리로 이동
cd korean_blog
```

### 2. 의존성 설정

`mix.exs`를 편집하여 필요한 의존성 추가:

```elixir
defp deps do
  [
    # Phoenix 핵심
    {:phoenix, "~> 1.8.3"},
    {:phoenix_ecto, "~> 4.4"},
    {:ecto_sql, "~> 3.10"},
    {:ecto_sqlite3, "~> 0.12"},
    {:phoenix_html, "~> 3.3"},
    {:phoenix_live_reload, "~> 1.4", only: :dev},
    {:phoenix_live_view, "~> 0.20"},
    {:floki, ">= 0.30.0", only: :test},
    {:phoenix_live_dashboard, "~> 0.8"},
    {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
    {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
    {:swoosh, "~> 1.3"},
    {:finch, "~> 0.13"},
    {:telemetry_metrics, "~> 0.6"},
    {:telemetry_poller, "~> 1.0"},
    {:gettext, "~> 0.20"},
    {:jason, "~> 1.2"},
    {:plug_cowboy, "~> 2.5"},

    # 마크다운 파싱
    {:earmark, "~> 1.4"},
    {:makeup, "~> 1.1"},
    {:makeup_elixir, "~> 0.16"},

    # 프론트매터용 YAML 파싱
    {:yaml_elixir, "~> 2.9"}
  ]
end
```

의존성 설치:

```bash
mix deps.get
```

### 3. 데이터베이스 설정

`config/dev.exs` 편집:

```elixir
# 데이터베이스 설정
config :korean_blog, KoreanBlog.Repo,
  database: Path.expand("../korean_blog_dev.db", Path.dirname(__ENV__.file)),
  pool_size: 5,
  show_sensitive_data_on_connection_error: true
```

`config/test.exs` 편집:

```elixir
config :korean_blog, KoreanBlog.Repo,
  database: Path.expand("../korean_blog_test.db", Path.dirname(__ENV__.file)),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10
```

### 4. Elixir i18n 설정

Elixir 로케일 디렉토리 생성:

```bash
mkdir -p priv/gettext/ko/LC_MESSAGES
```

`config/config.exs` 편집:

```elixir
config :korean_blog, KoreanBlogWeb.Gettext,
  default_locale: "ko",
  locales: ~w(ko en)
```

### 5. 데이터베이스 마이그레이션 생성

```bash
# posts 테이블 생성
mix ecto.gen.migration create_posts

# tags 테이블 생성
mix ecto.gen.migration create_tags

# post_tags 조인 테이블 생성
mix ecto.gen.migration create_post_tags

# subscriptions 테이블 생성
mix ecto.gen.migration create_subscriptions
```

`specs/001-korean-blog-site/data-model.md`에서 마이그레이션 코드를 생성된 마이그레이션 파일에 복사하세요.

마이그레이션 실행:

```bash
mix ecto.create
mix ecto.migrate
```

### 6. 샘플 블로그 포스트 생성

포스트 디렉토리 생성:

```bash
mkdir -p priv/posts
mkdir -p priv/static/images/thumbnails
```

`priv/posts/`에 샘플 마크다운 파일 추가 (형식은 data-model.md 참조).

### 7. 데이터베이스 시드

시딩 로직으로 `priv/repo/seeds.exs` 편집 (시드 스크립트는 data-model.md 참조).

시드 실행:

```bash
mix run priv/repo/seeds.exs
```

### 8. 프론트엔드 의존성 설치

```bash
# Node 패키지 설치
cd assets && npm install && cd ..

# Tailwind CSS 설치 및 설정
mix tailwind.install
```

### 9. 개발 서버 시작

```bash
# Phoenix 서버 시작
mix phx.server
```

브라우저에서 <http://localhost:4000> 방문.

---

## 빠른 시작 (Docker)

### 1. Dockerfile 생성

프로젝트 루트에 `Dockerfile` 생성:

```dockerfile
# 빌드 단계
FROM elixir:1.19-alpine AS build

# 빌드 의존성 설치
RUN apk add --no-cache build-base npm git sqlite-dev

# 작업 디렉토리 설정
WORKDIR /app

# hex와 rebar 설치
RUN mix local.hex --force && \
    mix local.rebar --force

# 환경을 프로덕션으로 설정
ENV MIX_ENV=prod

# mix 파일 복사 및 의존성 가져오기
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mix deps.compile

# 애플리케이션 소스 복사
COPY config config
COPY lib lib
COPY priv priv
COPY assets assets

# 자산 컴파일
RUN mix assets.deploy

# 릴리스 컴파일
RUN mix compile
RUN mix release

# 런타임 단계
FROM alpine:3.18 AS app

# 런타임 의존성 설치
RUN apk add --no-cache openssl ncurses-libs sqlite

WORKDIR /app

# 빌드 단계에서 릴리스 복사
COPY --from=build /app/_build/prod/rel/korean_blog ./

# 포스트 디렉토리 복사
COPY priv/posts ./priv/posts

# 포트 노출
EXPOSE 4000

# 환경 설정
ENV HOME=/app

# 릴리스 실행
CMD ["bin/korean_blog", "start"]
```

### 2. docker-compose.yml 생성

```yaml
version: '3.8'

services:
  web:
    build: .
    ports:
      - "4000:4000"
    environment:
      - SECRET_KEY_BASE=your_secret_key_base_here
      - DATABASE_PATH=/app/data/korean_blog.db
      - PHX_HOST=localhost
      - PORT=4000
    volumes:
      - ./data:/app/data
      - ./priv/posts:/app/priv/posts
    command: sh -c "mix ecto.create && mix ecto.migrate && mix run priv/repo/seeds.exs && mix phx.server"

  dev:
    build:
      context: .
      target: build
    ports:
      - "4000:4000"
    environment:
      - MIX_ENV=dev
      - DATABASE_PATH=/app/data/korean_blog_dev.db
    volumes:
      - .:/app
      - /app/deps
      - /app/_build
      - ./data:/app/data
    command: mix phx.server
    stdin_open: true
    tty: true
```

### 3. 빌드 및 실행

```bash
# 개발 모드
docker-compose run --rm dev mix deps.get
docker-compose run --rm dev mix ecto.create
docker-compose run --rm dev mix ecto.migrate
docker-compose run --rm dev mix run priv/repo/seeds.exs
docker-compose up dev

# 프로덕션 모드
docker-compose build
docker-compose up web
```

<http://localhost:4000> 방문

---

## 개발 워크플로우

### 테스트 실행

```bash
# 모든 테스트 실행
mix test

# 특정 테스트 파일 실행
mix test test/korean_blog_web/live/home_live_test.exs

# 커버리지와 함께 실행
mix test --cover
```

### Playwright 테스트 실행

```bash
# Playwright 설치 (MCP를 사용하지 않는 경우)
npm install -D @playwright/test

# Playwright 테스트 실행
npx playwright test

# UI와 함께 실행
npx playwright test --ui

# 특정 테스트 실행
npx playwright test tests/homepage.spec.js
```

### 코드 품질

```bash
# 코드 포맷팅
mix format

# 포맷팅 확인
mix format --check-formatted

# Credo 실행 (정적 분석)
mix credo

# Dialyzer 실행 (타입 검사)
mix dialyzer
```

### 데이터베이스 관리

```bash
# 데이터베이스 리셋
mix ecto.reset

# 마지막 마이그레이션 롤백
mix ecto.rollback

# 마이그레이션 상태 확인
mix ecto.migrations

# 새 마이그레이션 생성
mix ecto.gen.migration migration_name
```

### LiveView 개발

```bash
# Phoenix가 실행 중인 상태에서 IEx 콘솔 접근
iex -S mix phx.server

# IEx 내에서 모듈 재로드
recompile()
```

---

## 프로젝트 구조 빠른 참조

```text
korean_blog/
├── lib/
│   ├── korean_blog/           # 도메인 로직
│   │   ├── blog/              # 블로그 컨텍스트
│   │   │   ├── post.ex
│   │   │   ├── tag.ex
│   │   │   ├── subscription.ex
│   │   │   └── markdown_parser.ex
│   │   ├── repo.ex
│   │   └── application.ex
│   └── korean_blog_web/       # 웹 레이어
│       ├── components/        # LiveView 컴포넌트
│       ├── live/              # LiveView 페이지
│       ├── router.ex
│       └── endpoint.ex
├── test/                      # 테스트
├── priv/
│   ├── posts/                 # 마크다운 블로그 포스트
│   ├── static/images/         # 썸네일
│   ├── repo/migrations/       # 데이터베이스 마이그레이션
│   └── gettext/ko/            # Elixir 번역
├── assets/                    # 프론트엔드 자산
├── config/                    # 설정
├── Dockerfile
└── docker-compose.yml
```

---

## 일반적인 작업

### 새 블로그 포스트 추가

1. `priv/posts/`에 마크다운 파일 생성:

```bash
touch priv/posts/2024-12-29-new-post.md
```

1. 프론트매터와 콘텐츠 추가:

```markdown
---
title: "새로운 블로그 포스트"
author: "작성자"
tags: ["elixir", "phoenix"]
thumbnail: "/images/thumbnails/new-post.jpg"
summary: "포스트 요약"
published_at: 2024-12-29T00:00:00Z
is_popular: false
---

# 제목

본문 내용...
```

1. 데이터베이스 재시드:

```bash
mix ecto.reset
mix run priv/repo/seeds.exs
```

또는 IEx를 통해 프로그래밍 방식으로 삽입.

### Elixir 번역 업데이트

1. `priv/gettext/ko/LC_MESSAGES/default.po` 편집:

```po
msgid "Home"
msgstr "홈"

msgid "Categories"
msgstr "카테고리"
```

1. 번역 컴파일:

```bash
mix gettext.extract
mix gettext.merge priv/gettext
```

### 새 LiveView 컴포넌트 추가

1. 컴포넌트 파일 생성:

```bash
touch lib/korean_blog_web/components/my_component.ex
```

1. 컴포넌트 정의:

```elixir
defmodule KoreanBlogWeb.Components.MyComponent do
  use Phoenix.Component

  attr :title, :string, required: true

  def my_component(assigns) do
    ~H"""
    <div class="my-component">
      <h2><%= @title %></h2>
    </div>
    """
  end
end
```

1. LiveView에서 임포트:

```elixir
import KoreanBlogWeb.Components.MyComponent
```

---

## 문제 해결

### 데이터베이스 문제

**문제**: `mix ecto.create` 실패

**해결책**:

```bash
# SQLite가 설치되어 있는지 확인
sqlite3 --version

# config에서 데이터베이스 경로 확인
cat config/dev.exs | grep database
```

**문제**: "table already exists"로 마이그레이션 실패

**해결책**:

```bash
# 데이터베이스 리셋
mix ecto.reset
```

### 자산 컴파일 문제

**문제**: Tailwind CSS가 작동하지 않음

**해결책**:

```bash
# Tailwind 재설치
mix tailwind.install

# assets/tailwind.config.js 존재 확인
ls assets/tailwind.config.js
```

**문제**: JavaScript가 로드되지 않음

**해결책**:

```bash
# 자산 재빌드
cd assets && npm install && npm run deploy && cd ..
```

### LiveView 문제

**문제**: LiveView가 연결되지 않음 (웹소켓 오류)

**해결책**:

```bash
# config/dev.exs에서 엔드포인트 설정 확인
# live_reload가 올바르게 설정되어 있는지 확인

# 브라우저 콘솔에서 오류 확인
# 포트 4000이 차단되지 않았는지 확인
```

**문제**: 변경사항이 브라우저에 반영되지 않음

**해결책**:

```bash
# config/dev.exs에서 live_reload가 활성화되어 있는지 확인
config :korean_blog, KoreanBlogWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*(po)$",
      ~r"lib/korean_blog_web/(live|views)/.*(ex)$",
      ~r"lib/korean_blog_web/templates/.*(eex)$"
    ]
  ]
```

### Elixir 언어 문제

**문제**: Elixir 텍스트가 ���로 표시됨

**해결책**:

```bash
# 데이터베이스 인코딩이 UTF-8인지 확인
# config/config.exs에서 gettext 설정 확인

# 파일 인코딩 확인
file -I priv/posts/*.md
# charset=utf-8로 표시되어야 함
```

---

## 다음 단계

앱이 실행된 후:

1. **LiveView 페이지 구현**: HomeLive, PostLive, CategoryLive 생성
2. **컴포넌트 빌드**: Carousel, PostGrid, ToC 컴포넌트 구현
3. **스타일링 추가**: Tailwind CSS 설정, Elixir 타이포그래피 생성
4. **테스트 작성**: 도메인 로직용 ExUnit 테스트, LiveView 테스트, Playwright E2E 테스트
5. **샘플 콘텐츠 생성**: 프론트매터가 있는 50개의 Elixir 블로그 포스트 생성
6. **배포 설정**: 프로덕션 Docker 이미지, 환경 변수 설정

자세한 구현 작업은 `/speckit.tasks` 명령어 출력을 참조하세요.

---

## 유용한 리소스

- [Phoenix Framework 문서](https://hexdocs.pm/phoenix/overview.html)
- [Phoenix LiveView 문서](https://hexdocs.pm/phoenix_live_view/)
- [Ecto 문서](https://hexdocs.pm/ecto/)
- [Earmark 문서](https://hexdocs.pm/earmark/)
- [Tailwind CSS 문서](https://tailwindcss.com/docs)
- [Elixir School](https://elixirschool.com/)

---

## 지원

문제나 질문이 있는 경우:

1. 이 빠른 시작 가이드 확인
2. spec.md, research.md, data-model.md 검토
3. Phoenix와 LiveView 문서 확인
4. 예제를 위한 테스트 파일 검토
