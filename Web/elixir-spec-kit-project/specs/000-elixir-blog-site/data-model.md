# 데이터 모델: Elixir 블로그 사이트

**브랜치**: `001-korean-blog-site` | **날짜**: 2025-12-29
**목적**: 데이터베이스 스키마, 관계, 검증 규칙 정의

## 개요

데이터 모델은 하이브리드 저장 방식을 사용합니다:

- **SQLite 데이터베이스**: 효율적인 쿼리를 위한 메타데이터 (태그, 필터링, 구독)
- **마크다운 파일**: 사람이 읽기 쉽고 버전 관리가 가능한 블로그 포스트 콘텐츠

## 엔티티 관계 다이어그램

```text
┌─────────────────┐         ┌──────────────┐         ┌─────────────┐
│     Post        │────┬────│  PostTag     │────┬────│     Tag     │
│                 │    │    │ (조인 테이블)  │    │    │             │
│ - id            │    │    │ - post_id    │    │    │ - id        │
│ - slug          │    │    │ - tag_id     │    │    │ - name      │
│ - title         │    │    └──────────────┘    │    │ - slug      │
│ - author        │    │                        │    └─────────────┘
│ - summary       │    │                        │
│ - thumbnail     │    └────────── * : * ───────┘
│ - published_at  │
│ - is_popular    │
│ - reading_time  │
│ - content_path  │
└─────────────────┘

┌─────────────────┐
│  Subscription   │
│                 │
│ - id            │
│ - email (고유)   │
│ - subscribed_at │
└─────────────────┘
```

## 엔티티

### 1. Post

데이터베이스에 저장된 메타데이터와 마크다운 파일의 콘텐츠를 가진 블로그 포스트를 나타냅니다.

**테이블 이름**: `posts`

**스키마**:

| 필드 | 타입 | 제약조건 | 설명 |
| ----- | ---- | ----------- | ----------- |
| id | INTEGER | PRIMARY KEY, AUTO INCREMENT | 고유 식별자 |
| slug | VARCHAR(255) | NOT NULL, UNIQUE | URL 친화적 식별자 (파일명에서) |
| title | VARCHAR(500) | NOT NULL | 포스트 제목 (Elixir) |
| author | VARCHAR(255) | NOT NULL | 저자명 |
| summary | TEXT | NOT NULL | 포스트 간략 요약 |
| thumbnail | VARCHAR(255) | NOT NULL | 썸네일 이미지 경로/URL |
| published_at | DATETIME | NOT NULL, DEFAULT NOW | 발행 날짜/시간 |
| is_popular | BOOLEAN | NOT NULL, DEFAULT FALSE | 캐러셀/인기 섹션 플래그 |
| reading_time | INTEGER | NOT NULL | 예상 읽기 시간 (분) |
| content_path | VARCHAR(255) | NOT NULL, UNIQUE | priv/posts/의 마크다운 파일 경로 |
| inserted_at | DATETIME | NOT NULL, DEFAULT NOW | 레코드 생성 타임스탬프 |
| updated_at | DATETIME | NOT NULL, DEFAULT NOW | 레코드 업데이트 타임스탬프 |

**인덱스**:

- `idx_posts_slug` on `slug` (URL 조회용)
- `idx_posts_published_at` on `published_at` (시간순 정렬용)
- `idx_posts_is_popular` on `is_popular` (인기 포스트 쿼리용)

**검증 규칙**:

- `slug`: `[a-z0-9-]+` 패턴과 일치해야 함, 길이 1-255
- `title`: 필수, 최대 500자
- `author`: 필수, 최대 255자
- `summary`: 필수, 최대 1000자
- `thumbnail`: 필수, 유효한 파일 경로 또는 URL
- `published_at`: 미래 날짜일 수 없음
- `reading_time`: 양의 정수, 최소 1분
- `content_path`: 존재하는 마크다운 파일을 가리켜야 함

**비즈니스 규칙**:

- Slug는 마크다운 파일명에서 파생됨
- 읽기 시간은 시딩 중 콘텐츠 단어 수에서 계산됨
- `is_popular` 플래그가 캐러셀과 인기 그리드 포함을 결정함
- 콘텐츠는 `priv/posts/{content_path}.md`에 존재해야 함

---

### 2. Tag

블로그 포스트를 정리하기 위한 카테고리/태그를 나타냅니다.

**테이블 이름**: `tags`

**스키마**:

| 필드 | 타입 | 제약조건 | 설명 |
| ----- | ---- | ----------- | ----------- |
| id | INTEGER | PRIMARY KEY, AUTO INCREMENT | 고유 식별자 |
| name | VARCHAR(100) | NOT NULL, UNIQUE | 표시 이름 (Elixir) |
| slug | VARCHAR(100) | NOT NULL, UNIQUE | URL 친화적 식별자 |
| inserted_at | DATETIME | NOT NULL, DEFAULT NOW | 레코드 생성 타임스탬프 |
| updated_at | DATETIME | NOT NULL, DEFAULT NOW | 레코드 업데이트 타임스탬프 |

**인덱스**:

- `idx_tags_slug` on `slug` (URL 조회용)
- `idx_tags_name` on `name` (표시 정렬용)

**검증 규칙**:

- `name`: 필수, 고유, 최대 100자, Elixir 문자 허용
- `slug`: `[a-z0-9-]+` 패턴과 일치해야 함, 길이 1-100, 이름에서 자동 생성

**비즈니스 규칙**:

- 태그는 시딩 중 포스트 프론트매터에서 추출됨
- 태그 slug는 이름에서 자동 생성됨 (음역 또는 수동 매핑)
- 포스트는 여러 태그를 가질 수 있음 (다대다 관계)

---

### 3. PostTag (조인 테이블)

포스트와 태그 간의 다대다 관계.

**테이블 이름**: `post_tags`

**스키마**:

| 필드 | 타입 | 제약조건 | 설명 |
| ----- | ---- | ----------- | ----------- |
| id | INTEGER | PRIMARY KEY, AUTO INCREMENT | 고유 식별자 |
| post_id | INTEGER | NOT NULL, FOREIGN KEY → posts(id) | 포스트 참조 |
| tag_id | INTEGER | NOT NULL, FOREIGN KEY → tags(id) | 태그 참조 |
| inserted_at | DATETIME | NOT NULL, DEFAULT NOW | 레코드 생성 타임스탬프 |

**인덱스**:

- `idx_post_tags_post_id` on `post_id` (포스트별 태그 찾기용)
- `idx_post_tags_tag_id` on `tag_id` (태그별 포스트 찾기용)
- `unique_post_tag` unique constraint on `(post_id, tag_id)` (중복 방지)

**검증 규칙**:

- `post_id`: 존재하는 포스트를 참조해야 함
- `tag_id`: 존재하는 태그를 참조해야 함
- `(post_id, tag_id)` 조합은 고유해야 함

**캐스케이딩**:

- `post_id`와 `tag_id` 모두에 대해 ON DELETE CASCADE

---

### 4. Subscription

블로그 업데이트를 위한 이메일 구독을 나타냅니다.

**테이블 이름**: `subscriptions`

**스키마**:

| 필드 | 타입 | 제약조건 | 설명 |
| ----- | ---- | ----------- | ----------- |
| id | INTEGER | PRIMARY KEY, AUTO INCREMENT | 고유 식별자 |
| email | VARCHAR(255) | NOT NULL, UNIQUE | 구독자 이메일 주소 |
| subscribed_at | DATETIME | NOT NULL, DEFAULT NOW | 구독 타임스탬프 |
| inserted_at | DATETIME | NOT NULL, DEFAULT NOW | 레코드 생성 타임스탬프 |

**인덱스**:

- `idx_subscriptions_email` unique index on `email` (고유성 강제)

**검증 규칙**:

- `email`: 필수, 유효한 이메일 형식, 고유, 최대 255자
- 이메일 형식: 표준 RFC 5322 검증

**비즈니스 규칙**:

- 중복 이메일 제출은 친근한 메시지 반환 (이미 구독됨)
- MVP에서는 이메일 전송 없음 - 향후 사용을 위해 저장
- MVP에서는 구독 취소 기능 없음

---

## Ecto 스키마 정의 (Elixir)

### Post 스키마

```elixir
defmodule KoreanBlog.Blog.Post do
  use Ecto.Schema
  import Ecto.Changeset

  schema "posts" do
    field :slug, :string
    field :title, :string
    field :author, :string
    field :summary, :string
    field :thumbnail, :string
    field :published_at, :utc_datetime
    field :is_popular, :boolean, default: false
    field :reading_time, :integer
    field :content_path, :string

    many_to_many :tags, KoreanBlog.Blog.Tag, join_through: "post_tags"

    timestamps()
  end

  @required_fields ~w(slug title author summary thumbnail published_at reading_time content_path)a
  @optional_fields ~w(is_popular)a

  def changeset(post, attrs) do
    post
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:slug, min: 1, max: 255)
    |> validate_length(:title, max: 500)
    |> validate_length(:author, max: 255)
    |> validate_length(:summary, max: 1000)
    |> validate_number(:reading_time, greater_than: 0)
    |> validate_format(:slug, ~r/^[a-z0-9-]+$/)
    |> unique_constraint(:slug)
    |> unique_constraint(:content_path)
  end
end
```

### Tag 스키마

```elixir
defmodule KoreanBlog.Blog.Tag do
  use Ecto.Schema
  import Ecto.Changeset

  schema "tags" do
    field :name, :string
    field :slug, :string

    many_to_many :posts, KoreanBlog.Blog.Post, join_through: "post_tags"

    timestamps()
  end

  @required_fields ~w(name slug)a

  def changeset(tag, attrs) do
    tag
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, max: 100)
    |> validate_length(:slug, max: 100)
    |> validate_format(:slug, ~r/^[a-z0-9-]+$/)
    |> unique_constraint(:name)
    |> unique_constraint(:slug)
  end
end
```

### Subscription 스키마

```elixir
defmodule KoreanBlog.Blog.Subscription do
  use Ecto.Schema
  import Ecto.Changeset

  schema "subscriptions" do
    field :email, :string
    field :subscribed_at, :utc_datetime

    timestamps(updated_at: false)
  end

  @required_fields ~w(email)a

  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/)
    |> validate_length(:email, max: 255)
    |> unique_constraint(:email)
    |> put_subscribed_at()
  end

  defp put_subscribed_at(changeset) do
    if get_change(changeset, :subscribed_at) do
      changeset
    else
      put_change(changeset, :subscribed_at, DateTime.utc_now())
    end
  end
end
```

---

## 데이터베이스 마이그레이션

### 마이그레이션 1: Posts 테이블 생성

```elixir
defmodule KoreanBlog.Repo.Migrations.CreatePosts do
  use Ecto.Migration

  def change do
    create table(:posts) do
      add :slug, :string, null: false
      add :title, :string, null: false, size: 500
      add :author, :string, null: false
      add :summary, :text, null: false
      add :thumbnail, :string, null: false
      add :published_at, :utc_datetime, null: false
      add :is_popular, :boolean, default: false, null: false
      add :reading_time, :integer, null: false
      add :content_path, :string, null: false

      timestamps()
    end

    create unique_index(:posts, [:slug])
    create unique_index(:posts, [:content_path])
    create index(:posts, [:published_at])
    create index(:posts, [:is_popular])
  end
end
```

### 마이그레이션 2: Tags 테이블 생성

```elixir
defmodule KoreanBlog.Repo.Migrations.CreateTags do
  use Ecto.Migration

  def change do
    create table(:tags) do
      add :name, :string, null: false, size: 100
      add :slug, :string, null: false, size: 100

      timestamps()
    end

    create unique_index(:tags, [:name])
    create unique_index(:tags, [:slug])
  end
end
```

### 마이그레이션 3: PostTags 조인 테이블 생성

```elixir
defmodule KoreanBlog.Repo.Migrations.CreatePostTags do
  use Ecto.Migration

  def change do
    create table(:post_tags) do
      add :post_id, references(:posts, on_delete: :delete_all), null: false
      add :tag_id, references(:tags, on_delete: :delete_all), null: false

      timestamps(updated_at: false)
    end

    create index(:post_tags, [:post_id])
    create index(:post_tags, [:tag_id])
    create unique_index(:post_tags, [:post_id, :tag_id])
  end
end
```

### 마이그레이션 4: Subscriptions 테이블 생성

```elixir
defmodule KoreanBlog.Repo.Migrations.CreateSubscriptions do
  use Ecto.Migration

  def change do
    create table(:subscriptions) do
      add :email, :string, null: false
      add :subscribed_at, :utc_datetime, null: false

      timestamps(updated_at: false)
    end

    create unique_index(:subscriptions, [:email])
  end
end
```

---

## 쿼리 패턴

### 일반적인 쿼리

1. **캐러셀용 모든 인기 포스트 가져오기**:

   ```elixir
   from(p in Post, where: p.is_popular == true, order_by: [desc: p.published_at], preload: [:tags])
   ```

2. **태그별 포스트 가져오기**:

   ```elixir
   from(p in Post, join: t in assoc(p, :tags), where: t.slug == ^tag_slug, order_by: [desc: p.published_at])
   ```

3. **홈페이지용 태그와 함께 모든 포스트 가져오기**:

   ```elixir
   from(p in Post, order_by: [desc: p.published_at], preload: [:tags])
   ```

4. **태그와 함께 slug로 단일 포스트 가져오기**:

   ```elixir
   from(p in Post, where: p.slug == ^slug, preload: [:tags])
   ```

5. **이메일 구독 존재 확인**:

   ```elixir
   from(s in Subscription, where: s.email == ^email)
   ```

---

## 마크다운 파일 형식

### 파일 명명 규칙

```
priv/posts/YYYY-MM-DD-slug.md
```

**예시**: `priv/posts/2024-01-15-phoenix-liveview-basics.md`

### 프론트매터 형식 (YAML)

```yaml
---
title: "Phoenix LiveView 기본 가이드"
author: "김철수"
tags: ["elixir", "phoenix", "liveview"]
thumbnail: "/images/thumbnails/phoenix-liveview-basics.jpg"
summary: "Phoenix LiveView의 기본 개념과 사용법을 알아봅니다."
published_at: 2024-01-15T09:00:00Z
is_popular: true
---

# Phoenix LiveView 기본 가이드

본문 내용이 여기에 들어갑니다...

## 주요 개념

LiveView는 실시간 업데이트를 제공합니다.

...
```

### 프론트매터 필드 매핑

| 프론트매터 필드 | 데이터베이스 컬럼 | 처리 |
| ---------------- | --------------- | ---------- |
| `title` | `title` | 직접 매핑 |
| `author` | `author` | 직접 매핑 |
| `tags` | `tags` (조인 테이블을 통해) | 배열 파싱, 태그 생성/찾기 |
| `thumbnail` | `thumbnail` | 직접 매핑 |
| `summary` | `summary` | 직접 매핑 |
| `published_at` | `published_at` | ISO 8601 날짜시간 파싱 |
| `is_popular` | `is_popular` | 직접 매핑, 기본값 false |
| (계산됨) | `reading_time` | 콘텐츠 단어 수에서 계산 |
| (파일명) | `slug` | 파일명에서 추출 (날짜 이후) |
| (파일 경로) | `content_path` | 상대 경로 저장 |

---

## 상태 전환

### 포스트 생명주기

1. **생성** (시딩을 통해):
   - 프론트매터가 있는 마크다운 파일 파싱
   - 콘텐츠에서 읽기 시간 계산
   - 파일명에서 slug 추출
   - 데이터베이스에 삽입
   - 태그 생성/연관

2. **표시**:
   - 메타데이터를 위해 데이터베이스에서 쿼리
   - 파일에서 마크다운 콘텐츠 로드
   - 마크다운을 HTML로 파싱 및 렌더링
   - ETS에서 파싱된 HTML 캐시 (선택사항)

3. **업데이트** (향후):
   - 마크다운 파일 업데이트
   - 프론트매터 재파싱
   - 데이터베이스 레코드 업데이트
   - 캐시 지우기

### 구독 생명주기

1. **생성**:
   - 이메일 형식 검증
   - 고유성 확인
   - 타임스탬프와 함께 삽입
   - 성공/중복 메시지 반환

2. **저장**:
   - 데이터베이스에 지속
   - 이메일 전송 없음 (MVP)

---

## 데이터 시딩 전략

### 시드 스크립트 (`priv/repo/seeds.exs`)

```elixir
# priv/posts/의 모든 마크다운 파일 파싱
# 각 파일에 대해:
#   1. 프론트매터 추출 (YAML)
#   2. 읽기 시간 계산
#   3. 파일명에서 slug 파생
#   4. 태그 생성/찾기
#   5. 연관과 함께 포스트 생성
#   6. 파일 참조를 위한 content_path 저장

# 의사 코드:
posts_dir = Path.join(:code.priv_dir(:korean_blog), "posts")

posts_dir
|> File.ls!()
|> Enum.filter(&String.ends_with?(&1, ".md"))
|> Enum.each(fn filename ->
  # 프론트매터와 콘텐츠 파싱
  # 읽기 시간 계산
  # 포스트 생성 및 태그 연관
end)
```

### 샘플 데이터 요구사항

- 다양한 콘텐츠를 가진 50개의 블로그 포스트
- 10-15개의 구별되는 태그/카테고리
- 캐러셀용으로 `is_popular`로 플래그된 5-10개의 포스트
- Elixir 제목, 요약, 콘텐츠
- 다양한 읽기 시간 (3-15분)
- 현실적인 발행 날짜 (지난 6개월)

---

## 성능 고려사항

1. **인덱싱**: `slug`, `published_at`, `is_popular`, 조인 테이블 외래 키에 대한 중요한 인덱스
2. **캐싱**: 파싱된 마크다운 HTML을 위한 ETS 고려 (인기 포스트용 LRU 캐시)
3. **즉시 로딩**: N+1 쿼리를 피하기 위해 태그 미리 로드
4. **SQLite 최적화**: 읽기 중심 워크로드를 위한 PRAGMA 설정
5. **쿼리 제한**: 홈페이지 그리드 페이지네이션 (예: 섹션당 12개 포스트)

---

## 향후 확장

1. **저자 엔티티**: 현재 문자열, 별도 테이블이 될 수 있음
2. **댓글**: 포스트에 대한 외래 키가 있는 댓글 테이블 추가
3. **조회수 카운터**: 포스트 조회수 추적
4. **검색**: 제목, 요약, 콘텐츠에 대한 전문 검색
5. **초안 상태**: 상태 필드 추가 (초안/발행됨)
6. **예약 발행**: scheduled_at 필드 추가
