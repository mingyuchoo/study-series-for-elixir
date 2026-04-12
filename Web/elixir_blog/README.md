# Elixir Blog (Elixir 기술 블로그)

Phoenix LiveView로 구축된 Elixir 기술 블로그 플랫폼으로, Elixir와 Phoenix 관련 콘텐츠를 Elixir 현지화 및 독자 참여 기능과 함께 게시하도록 설계되었습니다.

## 주요 기능

### 콘텐츠 관리

- **마크다운 기반 포스트** YAML 프론트매터 메타데이터 포함
- **Elixir 읽기 시간 계산** (분당 250음절 + 250단어)
- **태그/카테고리 시스템** 콘텐츠 분류용
- **인기 포스트** 캐러셀 및 추천 콘텐츠
- **자동 목차 생성** 마크다운 헤딩에서 생성

### 독자 경험

- **반응형 디자인** 자동 진행 캐러셀 포함
- **카테고리 필터링** 태그별 포스트 탐색 및 카테고리 사이드바
- **이메일 구독 시스템** 중복 방지 기능
- **Elixir UI 현지화** (홈, 카테고리, 구독하기)
- **포스트 메타데이터 표시** (작성자, 읽기 시간, 게시일)
- **카테고리별 콘텐츠 그리드** 쉬운 탐색을 위한
- **일관된 네비게이션** 헤더와 푸터가 모든 페이지에 표시됨

### 기술 스택

- **Phoenix 1.8.3** LiveView 1.1.0 포함
- **SQLite 데이터베이스** Ecto ORM 사용
- **Tailwind CSS v4** 스타일링용
- **Earmark** 마크다운 파싱용
- **Elixir/영어** 이중 언어 지원
- **ETS 캐시** 마크다운 파싱 성능 최적화
- **SEO 최적화** Open Graph 및 Twitter Card 메타 태그 포함
- **Playwright** E2E 테스트용

## 시작하기

### 사전 요구사항

- Elixir 1.19+
- Phoenix 1.8+
- SQLite

### 설치

1. 의존성 설치:

```bash
mix setup
```

1. 샘플 콘텐츠로 데이터베이스 시드:

```bash
mix ecto.migrate
mix run priv/repo/seeds.exs
```

1. Phoenix 서버 시작:

```bash
mix phx.server
```

1. [`localhost:4000`](http://localhost:4000)에 접속하여 블로그 확인

### 콘텐츠 추가

블로그 포스트는 `priv/posts/`에 YAML 프론트매터와 함께 마크다운 파일로 저장됩니다:

```markdown
---
title: "포스트 제목"
author: "작성자 이름"
summary: "포스트에 대한 간단한 설명"
thumbnail: "/images/thumbnail.jpg"
published_at: "2024-01-01T00:00:00Z"
is_popular: false
tags: ["elixir", "phoenix"]
---

# 콘텐츠 제목

마크다운 콘텐츠가 여기에 들어갑니다...
```

새 포스트를 추가한 후, 시드 스크립트를 실행하여 데이터베이스를 업데이트하세요:

```bash
mix run priv/repo/seeds.exs
```

## 프로젝트 구조

```
lib/elixir_blog/
├── blog/                       # 블로그 컨텍스트 및 스키마
│   ├── post.ex                # 포스트 스키마
│   ├── tag.ex                 # 태그 스키마
│   ├── subscription.ex        # 이메일 구독 스키마
│   ├── markdown_parser.ex     # Elixir 인식 콘텐츠 처리
│   └── markdown_cache.ex      # ETS 기반 마크다운 캐시
└── elixir_blog_web/
    ├── live/                  # LiveView 페이지
    │   ├── home_live.ex       # 캐러셀과 그리드가 있는 홈페이지
    │   ├── post_live.ex       # 개별 포스트 표시
    │   └── category_live.ex   # 카테고리별 포스트 필터링
    └── components/            # 재사용 가능한 UI 컴포넌트
        ├── header.ex          # 네비게이션 헤더
        ├── footer.ex          # 사이트 푸터
        ├── carousel.ex        # 포스트 캐러셀
        ├── post_grid.ex       # 포스트 그리드 레이아웃
        ├── category_sidebar.ex # 카테고리 네비게이션
        └── ...
```

## 개발

이 프로젝트는 Phoenix v1.8 모범 사례를 따르며 다음을 포함합니다:

- 실시간 UI 업데이트를 위한 LiveView
- 컴포넌트 기반 아키텍처
- Gettext를 사용한 Elixir 현지화
- 반응형 디자인 패턴
- 이메일 구독 관리

자세한 개발 가이드라인은 `AGENTS.md`를 참조하세요.

## 테스트

E2E 테스트 실행하기:

```bash
# Playwright 의존성 설치 (처음 한 번만)
npm install
npx playwright install

# 모든 E2E 테스트 실행
npx playwright test

# 특정 테스트 파일 실행
npx playwright test test/e2e/navigation.spec.js
npx playwright test test/e2e/category-filter.spec.js
```

테스트 커버리지:

- 홈페이지 캐러셀 및 포스트 그리드
- 포스트 상세 페이지 및 목차
- 네비게이션 헤더/푸터
- 카테고리 필터링 및 사이드바
- 이메일 구독 양식

## 배포

프로덕션에서 실행할 준비가 되셨나요? [배포 가이드](https://hexdocs.pm/phoenix/deployment.html)를 확인해 주세요.

## 더 알아보기

- 공식 웹사이트: <https://www.phoenixframework.org/>
- 가이드: <https://hexdocs.pm/phoenix/overview.html>
- 문서: <https://hexdocs.pm/phoenix>
- 포럼: <https://elixirforum.com/c/phoenix-forum>
