# elixir-blog 개발 가이드라인

Phoenix LiveView로 구축된 Elixir 기술 블로그 플랫폼. 최종 업데이트: 2025-12-30

## 활성 기술

### 핵심 프레임워크

- **Elixir 1.19+** + **OTP 28.2**
- **Phoenix 1.8.3** + **Phoenix LiveView 1.1.0**
- **Ecto 3.13** + **SQLite3** 데이터베이스
- **Bandit 1.5** HTTP 서버 어댑터

### 프론트엔드 & 스타일링

- **Tailwind CSS v4.1.12** (유틸리티 우선 CSS)
- **esbuild 0.25.4** (JavaScript 번들러)
- **Heroicons v2.2.0** (아이콘 라이브러리)

### 콘텐츠 처리

- **Earmark 1.4** (Markdown 파서)
- **Makeup 1.1** (구문 강조)
- **YAML Elixir 2.9** (프론트매터 파싱)
- **HtmlSanitizeEx 1.4** (XSS 방지)

### 현지화 & 이메일

- **Gettext 1.0** (한국어/영어 i18n 지원)
- **Swoosh 1.16** (이메일 라이브러리)

### 모니터링 & 테스트

- **Telemetry 1.0** (메트릭 수집)
- **Playwright 1.40.0** (E2E 테스트)
- **Phoenix LiveDashboard 0.8.3** (개발 모니터링)

## 프로젝트 구조

```text
elixir_blog/
├── lib/
│   ├── elixir_blog/
│   │   ├── blog/                    # 블로그 컨텍스트
│   │   │   ├── post.ex             # 포스트 스키마
│   │   │   ├── tag.ex              # 태그 스키마
│   │   │   ├── subscription.ex     # 구독 스키마
│   │   │   ├── markdown_parser.ex  # 마크다운 파서 (한국어 지원)
│   │   │   └── markdown_cache.ex   # ETS 캐시
│   │   ├── blog.ex                 # 블로그 컨텍스트 API
│   │   └── repo.ex                 # Ecto 저장소
│   └── elixir_blog_web/
│       ├── live/
│       │   ├── home_live.ex        # 홈페이지 (캐러셀 + 그리드)
│       │   ├── post_live.ex        # 개별 포스트 (TOC 포함)
│       │   └── category_live.ex    # 카테고리 필터링
│       ├── components/             # 재사용 가능한 UI 컴포넌트
│       └── controllers/
├── priv/
│   ├── posts/                      # 마크다운 블로그 포스트
│   ├── static/images/              # 이미지 자산
│   └── repo/migrations/            # 데이터베이스 마이그레이션
├── test/
│   └── e2e/                        # Playwright E2E 테스트
├── assets/                         # 프론트엔드 자산
├── config/                         # 애플리케이션 설정
└── docker-compose.yml              # 개발/프로덕션 컨테이너
```

## 명령어

### 개발 환경

```bash
# 프로젝트 설정 (의존성, DB, 자산)
mix setup

# 개발 서버 시작 (포트 4000)
mix phx.server

# 데이터베이스 마이그레이션
mix ecto.migrate

# 시드 데이터 로드
mix run priv/repo/seeds.exs

# 테스트 실행
mix test

# E2E 테스트 실행
npx playwright test
```

### Docker 환경

```bash
# 개발 환경 시작
docker-compose up dev

# 프로덕션 환경 시작
docker-compose up prod

# 빌드만 실행
docker-compose build
```

### 자산 컴파일

```bash
# CSS/JS 자산 컴파일
mix assets.deploy

# 개발 모드 자산 감시
mix assets.setup
```

## 코드 스타일

### Elixir 규칙

- **표준 Elixir 포매터** 사용 (`.formatter.exs`)
- **컨텍스트 패턴** 준수 (Blog 컨텍스트)
- **LiveView 컴포넌트** 기반 UI 구조
- **Ecto 스키마** 및 **changeset** 패턴
- **문서화**: `@moduledoc` 및 `@doc` 주석 필수

### 한국어 지원 규칙

- **UTF-8 인코딩** 필수
- **한국어 문자 범위**: `0xAC00-0xD7A3` (유니코드)
- **읽기 시간 계산**: 분당 250음절 + 250단어
- **슬러그 생성**: 한국어 문자 지원 `[^\w\s가-힣-]`

### 프론트엔드 규칙

- **Tailwind CSS** 유틸리티 클래스 사용
- **반응형 디자인** (모바일 우선)
- **접근성** 준수 (ARIA 라벨, 시맨틱 HTML)
- **SEO 최적화** (Open Graph, Twitter Card)

## 데이터베이스 스키마

### Posts 테이블

- `slug` (고유, 인덱스)
- `title`, `author`, `summary`
- `thumbnail`, `content_path`
- `published_at` (인덱스), `is_popular` (인덱스)
- `reading_time` (계산된 값)

### Tags 테이블

- `name`, `slug` (고유)
- Posts와 다대다 관계

### Subscriptions 테이블

- `email` (고유), `subscribed_at`

## 성능 최적화

- **ETS 캐시**: 마크다운 파싱 결과 캐싱
- **데이터베이스 인덱스**: published_at, is_popular, slug
- **프리로딩**: N+1 쿼리 방지 (tags 관계)
- **자산 최적화**: 프로덕션에서 minification
- **Gzip 압축**: 정적 파일

## 보안 규칙

- **HTML 새니타이제이션**: XSS 방지
- **CSRF 보호**: Phoenix 기본 제공
- **보안 쿠키**: HTTPS 환경에서 secure 플래그
- **입력 검증**: Ecto changeset 사용
- **SQL 인젝션 방지**: Ecto 쿼리 사용

## 최근 변경사항

- **2025-12-30**: 코드베이스 분석 기반 가이드라인 현행화
- **한국어 블로그 플랫폼**: LiveView + 마크다운 기반 CMS
- **Docker 컨테이너화**: 개발/프로덕션 환경 분리
- **E2E 테스트**: Playwright 기반 자동화 테스트
- **성능 최적화**: ETS 캐시 및 데이터베이스 인덱싱

<!-- MANUAL ADDITIONS START -->
<!-- MANUAL ADDITIONS END -->

## Active Technologies
- Elixir 1.19 + OTP 28.2 + Phoenix 1.8.3, Phoenix LiveView 1.1.0, Ecto 3.13 (001-category-stats)
- SQLite3 with existing `posts` and `tags` tables (many-to-many relationship) (001-category-stats)

## Recent Changes
- 001-category-stats: Added Elixir 1.19 + OTP 28.2 + Phoenix 1.8.3, Phoenix LiveView 1.1.0, Ecto 3.13
