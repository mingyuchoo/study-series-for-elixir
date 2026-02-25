# 구현 계획: 카테고리별 포스트 통계 페이지

**브랜치**: `001-category-stats` | **날짜**: 2025-12-30 | **명세서**: [spec.md](./spec.md)
**입력**: `/specs/001-category-stats/spec.md`의 기능 명세서

## 요약

이 기능은 태그/카테고리별로 집계된 포스트 수를 표시하는 카테고리 통계 페이지를 구현합니다. 사용자는 블로그 헤더에서 이 페이지로 이동하여 두 개의 그리드 섹션(인기 포스트와 카테고리 분석)에서 통계를 보고, 각 카테고리를 클릭하여 필터링된 포스트 목록으로 이동할 수 있습니다. 구현은 기존 Phoenix LiveView 블로그 플랫폼을 새로운 CategoryStatsLive 모듈로 확장하고 일관성을 위해 기존 컴포넌트를 재사용합니다.

## 기술적 컨텍스트

**언어/버전**: Elixir 1.19 + OTP 28.2
**주요 의존성**: Phoenix 1.8.3, Phoenix LiveView 1.1.0, Ecto 3.13
**저장소**: 기존 `posts`와 `tags` 테이블이 있는 SQLite3 (다대다 관계)
**테스팅**: ExUnit (단위 테스트), Playwright 1.40.0 (E2E 테스트)
**대상 플랫폼**: 웹 (Bandit 1.5의 Phoenix 서버)
**프로젝트 타입**: 웹 애플리케이션 (Phoenix 모놀리스)
**성능 목표**:

- 카테고리 통계 페이지 로드 < 2초
- 카테고리 상세 페이지 로드 < 3초
- 100개 이상의 카테고리에서 < 5초 로드 시간 지원
**제약사항**:
- 카테고리 상세 페이지에 기존 홈페이지 레이아웃을 재사용해야 함 (FR-008, SC-005)
- 모바일 반응형 디자인 (최소 2열 그리드)
- 한국어 지원 (가나다 정렬)
**규모/범위**:
- 예상 1-3개의 새로운 LiveView 모듈
- 약 5개의 기존 컴포넌트 재사용 (Header, Footer, PostGrid 등)
- Blog 모듈에 2-3개의 새로운 컨텍스트 함수

## 헌법 검사

*게이트: 0단계 연구 전에 통과해야 함. 1단계 설계 후 재검사.*

### ✅ I. 명세서 우선 개발

- [x] 구현 전에 완전한 명세서(spec.md)가 있음
- [x] 우선순위(P1/P2)가 정의된 사용자 스토리
- [x] 수락 시나리오가 문서화됨
- [x] 성공 기준이 측정 가능함

### ✅ II. 사용자 스토리 중심 구성

- [x] 기능이 3개의 독립적인 사용자 스토리로 분해됨
- [x] 각 스토리가 독립적으로 테스트 가능함
- [x] 우선순위가 할당됨 (P1: 통계 페이지 & 상세 페이지, P2: 인기 섹션)
- [x] MVP가 P1 스토리에 집중함

### ✅ III. 테스트 우선 구현

- [x] 각 사용자 스토리에 E2E 테스트 필요 (Playwright)
- [x] 테스트가 처음에는 실패해야 함 (red-green-refactor)
- [x] 독립적인 테스트 기준이 정의됨

### ✅ IV. 설계에 의한 병렬화

- [x] 사용자 스토리가 병렬로 개발 가능함 (다른 라우트/모듈)
- [x] 컴포넌트 재사용으로 독립적인 작업 가능
- [x] 데이터베이스 쿼리가 추가적임 (스키마 변경 불필요)

### ✅ V. 품질 게이트 및 일관성

- [x] 이 단계에서 헌법 준수 검증됨
- [x] 명세서 품질 체크리스트 통과
- [x] 코딩 전에 아키텍처 계획 수립 (이 계획)

**헌법 준수**: ✅ 통과 - 모든 게이트 만족. 위반 사항 없음.

## 프로젝트 구조

### 문서 (이 기능)

```text
specs/001-category-stats/
├── spec.md              # 기능 명세서 (완료)
├── plan.md              # 이 파일 (현재 단계)
├── research.md          # 0단계 출력 (아키텍처 결정)
├── data-model.md        # 1단계 출력 (엔티티 정의)
├── quickstart.md        # 1단계 출력 (개발 가이드)
├── contracts/           # 1단계 출력 (API 계약)
│   └── blog_context.md  # Blog 컨텍스트 함수 계약
└── checklists/
    └── requirements.md  # 명세서 품질 체크리스트 (완료)
```

### 소스 코드 (저장소 루트)

```text
elixir_blog/
├── lib/
│   ├── elixir_blog/
│   │   ├── blog/                        # Blog 컨텍스트 (기존)
│   │   │   ├── post.ex                  # Post 스키마 (기존)
│   │   │   ├── tag.ex                   # Tag 스키마 (기존)
│   │   │   └── subscription.ex          # Subscription 스키마 (기존)
│   │   └── blog.ex                      # Blog 컨텍스트 API (확장)
│   └── elixir_blog_web/
│       ├── live/
│       │   ├── home_live.ex             # 홈페이지 (기존)
│       │   ├── post_live.ex             # 포스트 상세 (기존)
│       │   ├── category_live.ex         # 카테고리 상세 (기존 - 확장)
│       │   └── category_stats_live.ex   # 새로움: 카테고리 통계 개요
│       ├── components/                  # 재사용 가능한 UI 컴포넌트 (기존)
│       │   ├── header.ex                # 카테고리 링크가 있는 헤더 (확장)
│       │   ├── footer.ex                # 푸터 (기존)
│       │   ├── post_grid.ex             # 포스트 그리드 (기존 - 재사용)
│       │   └── category_grid.ex         # 새로움: 카테고리 통계 그리드
│       └── router.ex                    # 라우트 (확장)
├── test/
│   ├── elixir_blog/
│   │   └── blog_test.exs                # 컨텍스트 테스트 (확장)
│   ├── elixir_blog_web/
│   │   └── live/
│   │       └── category_stats_live_test.exs  # 새로움: LiveView 테스트
│   └── e2e/
│       ├── category_stats.spec.ts       # 새로움: 통계 페이지 E2E 테스트
│       └── category_navigation.spec.ts  # 새로움: 네비게이션 E2E 테스트
└── priv/
    ├── repo/
    │   └── migrations/                  # 새로운 마이그레이션 불필요
    └── posts/                           # 마크다운 포스트 (기존)
```

**구조 결정**: 기존 Phoenix 모놀리스 구조를 확장합니다. 카테고리 통계 기능은 새로운 CategoryStatsLive 모듈을 추가하고 기존 컴포넌트를 재사용하여 현재 LiveView 아키텍처와 원활하게 통합됩니다. 기존 CategoryLive는 필터링된 포스트 목록을 처리하고(사용자 스토리 3), 개요 페이지를 위한 CategoryStatsLive를 추가합니다(사용자 스토리 1 & 2).

## 복잡성 추적

> **헌법 검사에서 정당화해야 하는 위반사항이 있는 경우에만 작성**

*위반사항이 감지되지 않음 - 이 섹션은 해당 없음.*

## 0단계: 개요 및 연구

### 연구 질문

기술적 컨텍스트와 기능 요구사항을 바탕으로 다음 영역들을 조사해야 합니다:

1. **기존 CategoryLive 구현**: 현재 카테고리 상세 페이지는 어떻게 작동하며, 일관성을 위해 레이아웃을 어떻게 재사용할 수 있는가 (FR-008)?
2. **집계 쿼리 패턴**: 한국어/영어 정렬을 지원하면서 태그별 포스트 수를 계산하는 최적의 Ecto 쿼리 패턴은 무엇인가 (FR-005)?
3. **그리드 컴포넌트 설계**: 카테고리 통계를 표시하기 위해 새로운 CategoryGrid 컴포넌트를 생성해야 하는가, 아니면 PostGrid를 확장해야 하는가?
4. **라우트 구조**: 카테고리 통계 개요 페이지에 어떤 라우트 패턴을 사용해야 하는가 (`/categories` vs `/categories/stats`)?
5. **성능 최적화**: 2초 로드 시간 요구사항(SC-001)을 충족하기 위해 카테고리 통계에 대한 캐싱을 어떻게 처리해야 하는가?

### 연구 작업

- 기존 CategoryLive 모듈을 연구하고 재사용 가능한 패턴 식별
- 포스트 통계를 위한 `group_by`와 `count`가 있는 Ecto 집계 쿼리 조사
- 리소스 스타일 라우트에 대한 Phoenix 라우팅 모범 사례 검토
- 확장 기회를 위한 기존 그리드 컴포넌트(PostGrid) 분석
- Ecto 쿼리에서 한국어/영어 혼합 정렬 연구 (콜레이션)

**출력**: `research.md`가 결과와 아키텍처 결정을 문서화할 것입니다

## 1단계: 설계 및 계약

### 데이터 모델

**엔티티** (spec.md에서):

- 카테고리/태그 (기존): name, slug, post_count (계산됨)
- 포스트 (기존): title, author, thumbnail, published_at, is_popular, tags
- 카테고리 통계 (가상): 태그별 집계된 포스트 수

**데이터베이스 변경**: 불필요 - `posts_tags` 조인 테이블이 있는 기존 `posts`와 `tags` 테이블이 모든 요구사항을 지원합니다

### API 계약

추가할 새로운 Blog 컨텍스트 함수:

1. `list_tags_with_post_counts()` - 집계된 포스트 수가 있는 모든 태그 반환
2. `list_tags_with_post_counts(sort: :alphabetical | :post_count)` - 정렬 옵션 포함
3. (기존) `list_popular_posts(limit: integer)` - 인기 섹션에 재사용
4. (기존) `list_posts_by_category(tag_slug, opts)` - 카테고리 상세에 재사용

새로운 LiveView 모듈:

1. `CategoryStatsLive` - 인기 + 카테고리 그리드가 있는 개요 페이지
   - 마운트: 인기 포스트 + 수가 포함된 모든 태그 로드
   - 렌더: 2섹션 그리드 레이아웃
2. (확장) `CategoryLive` - 카테고리 상세 페이지 (이미 존재)
   - 홈페이지와의 레이아웃 일관성 확인

**출력**:

- `data-model.md` - 엔티티 정의와 관계
- `contracts/blog_context.md` - 함수 시그니처와 동작
- `quickstart.md` - 개발 설정 지침

### 에이전트 컨텍스트 업데이트

1단계 완료 후, 새로운 기술/패턴으로 에이전트 컨텍스트를 업데이트:

- `.specify/scripts/bash/update-agent-context.sh claude` 실행
- CategoryStatsLive 모듈 패턴 추가
- 카테고리 집계 쿼리 패턴 문서화

## 2단계: 작업 (연기됨)

2단계 작업 분해는 이 계획이 승인된 후 `/speckit.tasks` 명령으로 생성됩니다. 작업은 다음과 같이 구성됩니다:

1. **설정 단계**: 라우트 설정, 테스트 인프라
2. **기초 단계**: Blog 컨텍스트 함수, 데이터베이스 쿼리
3. **사용자 스토리 단계**:
   - P1: 카테고리 통계 개요 페이지 (사용자 스토리 1)
   - P2: 인기 포스트 섹션 (사용자 스토리 2)
   - P1: 카테고리 상세 일관성 (사용자 스토리 3)
4. **마무리 단계**: 반응형 디자인, 한국어 정렬, 성능 최적화

각 작업은 다음으로 표시됩니다:

- `[P]` 병렬화 가능한 작업
- `[US-1]`, `[US-2]`, `[US-3]` 사용자 스토리 연관
- 명확한 파일 경로와 수락 기준

## 다음 단계

1. 0단계 연구 완료 (`research.md` 생성)
2. 1단계 설계 완료 (`data-model.md`, `contracts/`, `quickstart.md` 생성)
3. `.specify/scripts/bash/update-agent-context.sh claude`로 에이전트 컨텍스트 업데이트
4. 설계 후 헌법 검사 재평가
5. 2단계 작업 생성을 위해 `/speckit.tasks`로 진행
