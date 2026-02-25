# 작업: 카테고리별 포스트 통계 페이지

**입력**: `/specs/001-category-stats/`의 설계 문서
**전제조건**: plan.md, spec.md, research.md, data-model.md, contracts/blog_context.md

**테스트**: 이 기능은 테스트 우선 개발을 따릅니다. E2E 테스트는 사용자 스토리를 검증하기 위해 구현 전에 작성됩니다.

**구성**: 작업은 사용자 스토리별로 그룹화되어 각 스토리의 독립적인 구현과 테스트를 가능하게 합니다.

## 형식: `[ID] [P?] [Story] 설명`

- **[P]**: 병렬 실행 가능 (다른 파일, 의존성 없음)
- **[Story]**: 이 작업이 속한 사용자 스토리 (US1, US2, US3)
- 설명에 정확한 파일 경로 포함

## 경로 규칙

이것은 Phoenix 모놀리스 프로젝트입니다:

- **애플리케이션 코드**: `elixir_blog/lib/elixir_blog/` (컨텍스트) 및 `elixir_blog/lib/elixir_blog_web/` (웹)
- **테스트**: `elixir_blog/test/elixir_blog/` (컨텍스트) 및 `elixir_blog/test/elixir_blog_web/` (웹)
- **E2E 테스트**: `elixir_blog/test/e2e/` (Playwright 테스트)

---

## Phase 1: 설정 (공유 인프라)

**목적**: 프로젝트 초기화 및 라우팅 구성

- [x] T001 CategoryStatsLive를 위해 elixir_blog/lib/elixir_blog_web/router.ex에 `/categories` 라우트 추가
- [x] T002 [P] 아직 구성되지 않은 경우 elixir_blog/test/e2e/에 Playwright E2E 테스트 인프라 설정
- [x] T003 [P] 기존 데이터베이스 스키마에 posts, tags, posts_tags 테이블이 있는지 확인 (마이그레이션 불필요)

---

## Phase 2: 기초 (차단 전제조건)

**목적**: 모든 사용자 스토리가 의존하는 핵심 Blog 컨텍스트 함수

**⚠️ 중요**: 이 단계가 완료될 때까지 사용자 스토리 작업을 시작할 수 없습니다

- [x] T004 Ecto 서브쿼리 패턴을 사용하여 elixir_blog/lib/elixir_blog/blog.ex에 `list_tags_with_post_counts/1` 함수 구현 (구현 세부사항은 contracts/blog_context.md 참조)
- [x] T005 elixir_blog/test/elixir_blog/blog_test.exs에 `list_tags_with_post_counts/1`에 대한 단위 테스트 추가 (알파벳 정렬, post_count 정렬, 빈 카테고리, 한국어 이름 테스트)

**체크포인트**: 기초 준비 완료 - 이제 사용자 스토리 구현을 병렬로 시작할 수 있습니다

---

## Phase 3: 사용자 스토리 1 - 카테고리 통계 개요 페이지 조회 (우선순위: P1) 🎯 MVP

**목표**: 인기 포스트 그리드와 카테고리 통계 그리드가 있는 카테고리 통계 개요 페이지 표시

**독립 테스트**: `/categories`로 이동, 두 개의 그리드(인기 포스트 및 카테고리 통계)가 있는 페이지 로드 확인, 각 카테고리는 이름과 포스트 수 표시

### 사용자 스토리 1을 위한 테스트

> **참고: 이 테스트들을 먼저 작성하고, 구현 전에 실패하는지 확인하세요**

- [x] T006 [P] [US1] 카테고리 통계 페이지 네비게이션 및 표시를 위한 E2E 테스트 파일 elixir_blog/test/e2e/category_stats.spec.ts 생성
- [x] T007 [P] [US1] 페이지 제목, 카테고리 그리드 존재, 포스트 수를 확인하는 "카테고리 통계 개요 표시" E2E 테스트 케이스 작성
- [x] T008 [P] [US1] 마운트 성공 및 데이터 로딩을 위한 elixir_blog/test/elixir_blog_web/live/category_stats_live_test.exs에 LiveView 테스트 작성

### 사용자 스토리 1을 위한 구현

- [x] T009 [P] [US1] categories, title, columns 속성을 가진 elixir_blog/lib/elixir_blog_web/components/category_grid.ex에 CategoryGrid 컴포넌트 생성
- [x] T010 [US1] 카테고리와 인기 포스트를 로드하는 mount/3 함수를 가진 elixir_blog/lib/elixir_blog_web/live/category_stats_live.ex에 CategoryStatsLive 모듈 생성
- [x] T011 [US1] 두 섹션 레이아웃으로 CategoryStatsLive에 render/1 함수 구현: 인기 포스트(PostGrid 사용) 및 카테고리 통계(CategoryGrid 사용)
- [x] T012 [US1] CategoryStatsLive assigns에 SEO 메타데이터(page_title, meta_description, og_type) 추가
- [x] T013 [US1] Tailwind CSS 반응형 그리드로 CategoryGrid 컴포넌트 스타일링 (모바일 1열, 데스크톱 2-3열, SC-007에 따라 최소 2열)

**체크포인트**: 이 시점에서 사용자 스토리 1이 완전히 기능해야 합니다 - `/categories` 페이지가 인기 포스트와 카테고리 통계를 독립적으로 표시

---

## Phase 4: 사용자 스토리 2 - 인기 포스트 통계 표시 (우선순위: P2)

**목표**: 적절한 빈 상태 처리와 함께 카테고리 통계 페이지에 인기 포스트 섹션 표시

**독립 테스트**: `/categories`로 이동, `is_popular: true`로 표시된 포스트가 있는 인기 포스트 섹션이 상단에 표시되는지 확인, 또는 인기 포스트가 없으면 빈 상태 메시지 표시

### 사용자 스토리 2를 위한 테스트

- [x] T014 [P] [US2] 인기 포스트 그리드가 나타나는지 확인하는 elixir_blog/test/e2e/category_stats.spec.ts에 "인기 포스트 섹션 표시" E2E 테스트 케이스 추가
- [x] T015 [P] [US2] 적절한 메시지가 표시되는지 확인하는 "인기 포스트가 없을 때 빈 상태 표시" E2E 테스트 케이스 추가
- [x] T016 [P] [US2] is_popular 필터링을 확인하는 category_stats_live_test.exs에 "인기 포스트 로드" LiveView 테스트 케이스 추가

### 사용자 스토리 2를 위한 구현

- [x] T017 [US2] CategoryStatsLive render/1에 인기 포스트 섹션 조건부 렌더링 추가 (@popular_posts가 비어있는지 확인)
- [x] T018 [US2] 사용자 친화적인 메시지와 스타일링으로 인기 포스트 섹션 빈 상태 UI 구현
- [x] T019 [US2] 인기 포스트가 published_at 내림차순으로 정렬되는지 확인 (Blog.list_popular_posts/1에 이미 구현됨)
- [x] T020 [US2] 적절한 스타일링으로 인기 포스트 그리드에 "인기 포스트" 섹션 제목 추가

**체크포인트**: 이 시점에서 사용자 스토리 1과 2가 모두 독립적으로 작동해야 합니다 - 인기 섹션이 올바르게 표시되거나 빈 상태를 보여줍니다

---

## Phase 5: 사용자 스토리 3 - 카테고리 상세 페이지 탐색 (우선순위: P1)

**목표**: 카테고리 통계 그리드에서 필터링된 포스트가 있는 카테고리 상세 페이지로의 네비게이션 활성화

**독립 테스트**: `/categories` 페이지에서 카테고리 카드 클릭, `/categories/:slug`로의 네비게이션 확인, 필터링된 포스트 표시 확인, 레이아웃이 홈페이지 구조와 일치하는지 확인

**참고**: CategoryLive는 이미 존재하며 이 기능을 구현합니다. 이 단계는 통합과 검증에 중점을 둡니다.

### 사용자 스토리 3을 위한 테스트

- [x] T021 [P] [US3] 엔드투엔드 네비게이션 플로우를 위한 E2E 테스트 파일 elixir_blog/test/e2e/category_navigation.spec.ts 생성
- [x] T022 [P] [US3] 카테고리 카드 클릭이 올바른 URL로 이동하는지 확인하는 "클릭 시 카테고리 상세로 이동" E2E 테스트 케이스 작성
- [x] T023 [P] [US3] 선택된 태그가 있는 포스트만 표시되는지 확인하는 "카테고리 상세 페이지에 필터링된 포스트 표시" E2E 테스트 케이스 작성
- [x] T024 [P] [US3] 일관된 Header, Footer, PostGrid 컴포넌트를 확인하는 "카테고리 상세 레이아웃이 홈페이지와 일치" E2E 테스트 케이스 작성

### 사용자 스토리 3을 위한 구현

- [x] T025 [US3] Phoenix.Component.link/1을 사용하여 `/categories/#{category.slug}`로 이동하는 CategoryGrid 컴포넌트 카드에 클릭 가능한 링크 추가
- [x] T026 [US3] CategoryGrid 컴포넌트의 카테고리 카드에 호버 효과 추가 (호버 시 shadow-xl 전환)
- [x] T027 [US3] 기존 CategoryLive (elixir_blog/lib/elixir_blog_web/live/category_live.ex)가 적절한 메시지로 빈 카테고리 케이스를 처리하는지 확인 (수락 시나리오 5)
- [x] T028 [US3] 카테고리 카드가 클릭 가능함을 보여주는 시각적 표시기(아이콘 또는 화살표) 추가

**체크포인트**: 이제 모든 사용자 스토리가 독립적으로 기능해야 합니다 - 홈 → 카테고리 → 카테고리 상세 → 포스트의 완전한 네비게이션 플로우

---

## Phase 6: 마무리 및 교차 관심사

**목적**: 여러 사용자 스토리에 영향을 미치고 기능 품질을 완성하는 개선사항

- [x] T029 [P] elixir_blog/lib/elixir_blog_web/components/header.ex의 Header 컴포넌트를 업데이트하여 `/categories`를 가리키는 "카테고리" 네비게이션 링크 추가
- [x] T030 [P] CategoryStatsLive에서 한국어/영어 혼합 태그 정렬이 올바르게 작동하는지 확인 (FR-005에 따른 가나다/알파벳 순서)
- [x] T031 [P] 모바일 기기에서 반응형 디자인 테스트 - 카테고리에 대한 최소 2열 그리드 확인 (SC-007)
- [x] T032 [P] 성능 테스트: 100개 이상의 카테고리로 `/categories` 페이지가 2초 이내에 로드되는지 확인 (SC-001)
- [x] T033 [P] 성능 테스트: 카테고리 상세 페이지가 3초 이내에 로드되는지 확인 (SC-002)
- [x] T034 [P] 포스트 수 정확성 확인 - 표시된 수와 실제 데이터베이스 수를 비교하는 데이터 무결성 검사 실행 (SC-006)
- [x] T035 CategoryGrid 카드와 네비게이션 링크에 접근성 속성(ARIA 레이블) 추가
- [x] T036 [P] 3개의 사용자 스토리가 모두 함께 작동하는지 검증하기 위해 전체 E2E 테스트 스위트 실행 (카테고리 통계 관련 13/13 테스트 통과)
- [x] T037 [P] 코드 포맷팅 및 린팅 - 모든 새로운/수정된 파일에 `mix format` 실행
- [x] T038 quickstart.md의 수동 테스트 체크리스트 - 모든 수락 시나리오 확인

---

## 의존성 및 실행 순서

### 단계 의존성

- **설정 (Phase 1)**: 의존성 없음 - 즉시 시작 가능
- **기초 (Phase 2)**: 설정 완료에 의존 - 모든 사용자 스토리를 차단
- **사용자 스토리 (3-Phase 5)**: 모두 기초 단계 완료에 의존
  - 사용자 스토리는 병렬로 진행 가능 (인력이 있는 경우)
  - 또는 우선순위 순서로 순차적으로 (P1 스토리 먼저: US1, US3, 그 다음 P2: US2)
- **마무리 (Phase 6)**: 모든 사용자 스토리 완료에 의존

### 사용자 스토리 의존성

- **사용자 스토리 1 (P1)**: 기초 (Phase 2) 후 시작 가능 - 다른 스토리에 의존성 없음
- **사용자 스토리 2 (P2)**: 기초 (Phase 2) 후 시작 가능 - US1과 통합되지만 독립적으로 테스트 가능 (인기 섹션은 카테고리 그리드와 분리됨)
- **사용자 스토리 3 (P1)**: 기초 (Phase 2) 후 시작 가능 - 네비게이션 소스를 위해 US1에 의존하지만 CategoryLive는 이미 존재

**MVP를 위한 중요 경로** (사용자 스토리 1만):

```
설정 (T001-T003) → 기초 (T004-T005) → US1 테스트 (T006-T008) → US1 구현 (T009-T013) → MVP 완료
```

### 각 사용자 스토리 내에서

- E2E 테스트는 먼저 작성되고 구현 전에 실패해야 합니다
- LiveView 구현 전에 LiveView 테스트 작성
- LiveView 모듈 전에 컴포넌트 (CategoryStatsLive 전에 CategoryGrid)
- 스타일링/마무리 전에 핵심 렌더링
- 다음 우선순위로 이동하기 전에 스토리 완료 및 테스트

### 병렬 기회

#### Phase 1 (설정)

- T001, T002, T003은 모두 병렬 실행 가능 (다른 관심사)

#### Phase 2 (기초)

- T004는 T005 전에 완료되어야 함 (테스트가 구현에 의존)

#### 사용자 스토리 1 (Phase 3)

```bash
# 병렬 배치 1: 모든 테스트
T006, T007, T008은 병렬 실행 가능 (다른 테스트 파일)

# 병렬 배치 2: 컴포넌트
T009는 독립적으로 실행 가능 (CategoryGrid 컴포넌트)

# 순차적: LiveView 구현은 컴포넌트에 의존
T010 → T011 → T012 → T013
```

#### 사용자 스토리 2 (Phase 4)

```bash
# 병렬 배치 1: 모든 테스트
T014, T015, T016은 병렬 실행 가능 (다른 테스트 케이스/파일)

# 순차적: 기존 LiveView에 대한 UI 개선
T017 → T018 → T019 → T020
```

#### 사용자 스토리 3 (Phase 5)

```bash
# 병렬 배치 1: 모든 테스트
T021, T022, T023, T024는 병렬 실행 가능 (별도 파일의 E2E 테스트)

# 병렬 배치 2: 컴포넌트 개선
T025, T026, T028은 병렬 실행 가능 (다른 스타일링 관심사)

# 독립적: 검증 작업
T027은 언제든지 실행 가능 (단순 검증, 변경 없음)
```

#### Phase 6 (마무리)

- T029, T030, T031, T032, T033, T034, T035, T037은 모두 병렬 실행 가능 (다른 파일/관심사)
- T036, T038은 다른 마무리 작업 완료 후 실행해야 함 (통합 검증)

---

## 병렬 예시: 사용자 스토리 1

```bash
# Phase 1: 모든 테스트를 병렬로 작성 (처음에는 실패)
작업: "E2E 테스트 파일 category_stats.spec.ts 생성"
작업: "카테고리 통계 개요 표시 E2E 테스트 케이스 작성"
작업: "마운트 성공을 위한 LiveView 테스트 작성"

# Phase 2: 컴포넌트 구현
작업: "components/category_grid.ex에 CategoryGrid 컴포넌트 생성"

# Phase 3: LiveView 구현 (순차적 단계)
작업: "live/category_stats_live.ex에 CategoryStatsLive 생성"
작업: "두 섹션 레이아웃으로 render 함수 구현"
작업: "SEO 메타데이터 추가"
작업: "Tailwind CSS로 CategoryGrid 스타일링"

# Phase 4: 테스트가 이제 통과하는지 확인
# 실행: mix test && npx playwright test
```

---

## 병렬 예시: 팀 전략

```bash
# 기초 단계 완료 후:

# 개발자 A: 사용자 스토리 1 (P1 - MVP)
T006-T013 (카테고리 통계 개요)

# 개발자 B: 사용자 스토리 2 (P2)
T014-T020 (인기 포스트 섹션)

# 개발자 C: 사용자 스토리 3 (P1)
T021-T028 (카테고리 네비게이션)

# 모든 개발자가 Phase 6(마무리)에서 합류
T029-T038 (교차 개선사항)
```

---

## 구현 전략

### MVP 우선 (사용자 스토리 1만)

1. Phase 1 완료: 설정 (T001-T003)
2. Phase 2 완료: 기초 (T004-T005) → **중요 차단 요소**
3. Phase 3 완료: 사용자 스토리 1 (T006-T013)
4. **중지 및 검증**:
   - E2E 테스트 실행: `cd elixir_blog/test/e2e && npx playwright test category_stats.spec.ts`
   - 수동 테스트: <http://localhost:4000/categories>로 이동
   - 확인: 인기 포스트 그리드 + 카테고리 통계 그리드가 올바르게 표시됨
5. 준비되면 배포/데모 → **MVP 전달**

**MVP 정의**: 사용자가 `/categories`로 이동하여 포스트 수와 함께 모든 카테고리 통계를 볼 수 있음

### 점진적 전달 (권장)

1. **기초** (1-Phase 2): 설정 + 핵심 Blog 함수 → 기초 준비
2. **MVP** (Phase 3): 사용자 스토리 1 → 독립적으로 테스트 → **배포/데모** (MVP!)
3. **개선 1** (Phase 5): 사용자 스토리 3 → 독립적으로 테스트 → 배포/데모 (네비게이션 작동)
4. **개선 2** (Phase 4): 사용자 스토리 2 → 독립적으로 테스트 → 배포/데모 (인기 섹션 완료)
5. **프로덕션 준비** (Phase 6): 마무리 → 최종 검증 → 프로덕션 배포

각 증분은 이전 기능을 깨뜨리지 않고 가치를 추가합니다.

### 병렬 팀 전략

여러 개발자와 함께 (기초 단계 완료 후):

**1주차**:

- **개발자 A**: 사용자 스토리 1 완료 (T006-T013) → MVP 준비
- **개발자 B**: 사용자 스토리 3 완료 (T021-T028) → 네비게이션 준비
- **개발자 C**: 사용자 스토리 2 완료 (T014-T020) → 인기 섹션 준비

**2주차**:

- **모든 개발자**: 마무리 단계 (T029-T038) → 프로덕션 준비

**이점**: 모든 P1 기능 (US1, US3)이 1주차에 완료되고, P2 기능 (US2)도 동시에 완료됨

---

## 테스트 전략

### 테스트 실행 순서

1. **단위 테스트 우선** (기초 단계):

   ```bash
   mix test test/elixir_blog/blog_test.exs
   # list_tags_with_post_counts/1이 올바르게 작동하는지 확인
   ```

2. **LiveView 테스트** (사용자 스토리별):

   ```bash
   mix test test/elixir_blog_web/live/category_stats_live_test.exs
   # CategoryStatsLive가 마운트되고 올바르게 렌더링되는지 확인
   ```

3. **E2E 테스트** (사용자 스토리별):

   ```bash
   cd elixir_blog/test/e2e
   npx playwright test category_stats.spec.ts
   npx playwright test category_navigation.spec.ts
   # 엔드투엔드 사용자 여정 확인
   ```

4. **전체 테스트 스위트** (마무리 단계):

   ```bash
   mix test  # 모든 Elixir 테스트
   cd test/e2e && npx playwright test  # 모든 E2E 테스트
   ```

### 테스트 커버리지 목표

- **Blog 컨텍스트 함수**: 100% 커버리지 (T005)
- **CategoryStatsLive**: 마운트 + 렌더 + assigns (T008)
- **E2E 사용자 여정**: 모든 3개 사용자 스토리 (T006-T007, T014-T016, T021-T024)
- **엣지 케이스**: 빈 카테고리, 인기 포스트 없음, 한국어 정렬

### 성능 테스트

마무리 단계에 포함된 성능 테스트:

- **T032**: 카테고리 통계 페이지 로드 (100개 이상 카테고리로 2초 이내)
- **T033**: 카테고리 상세 페이지 로드 (3초 이내)
- **T034**: 포스트 수 정확성 (데이터베이스와 100% 일치)

성능 검증을 위해 Playwright 타이밍 API 또는 `mix profile` 사용.

---

## 참고사항

- **[P] 작업** = 다른 파일, 의존성 없음 - 병렬화 안전
- **[Story] 레이블** = 추적 가능성을 위해 작업을 특정 사용자 스토리에 매핑
- **각 사용자 스토리 독립적으로 완료 가능** = US2/US3 없이 US1 배포 가능
- **테스트 우선 접근법** = 구현 전에 E2E 및 LiveView 테스트 작성
- **기존 코드 재사용** = CategoryLive, PostGrid, Header, Footer 이미 존재
- **데이터베이스 마이그레이션 없음** = 모든 테이블과 컬럼이 이미 존재
- **한국어 지원** = 네이티브 UTF-8 콜레이션, 특별한 구성 불필요

### 피해야 할 것

- ❌ 테스트 건너뛰기 - 항상 테스트를 먼저 작성 (빨간색-녹색-리팩토링)
- ❌ CategoryLive를 불필요하게 수정 - US3에 대해 이미 작동함
- ❌ 새로운 Post/Tag 스키마 생성 - 기존 엔티티 사용
- ❌ 라우트 하드코딩 - Phoenix 라우트 헬퍼 사용 (~p"/categories")
- ❌ 테스트 전에 모든 스토리 구현 - 각 스토리를 독립적으로 테스트
- ❌ 조기 최적화 - 캐싱 추가 전에 성능 측정

### 성공 기준 검증

구현 후 spec.md의 모든 성공 기준 확인:

- ✅ **SC-001**: 카테고리 통계 페이지가 2초 이내에 로드 (T032)
- ✅ **SC-002**: 카테고리 상세 페이지가 3초 이내에 로드 (T033)
- ✅ **SC-003**: 100개 이상 카테고리가 5초 이내에 로드 (T032)
- ✅ **SC-004**: 3클릭 네비게이션 (홈 → 카테고리 → 상세 → 포스트) (T036)
- ✅ **SC-005**: 홈페이지와 시각적 일관성 (T024)
- ✅ **SC-006**: 100% 정확한 포스트 수 (T034)
- ✅ **SC-007**: 모바일 2개 이상 열 그리드 (T031)

---

## 빠른 참조

**총 작업**: 38개

- **설정**: 3개 작업 (T001-T003)
- **기초**: 2개 작업 (T004-T005)
- **사용자 스토리 1 (P1)**: 8개 작업 (T006-T013)
- **사용자 스토리 2 (P2)**: 7개 작업 (T014-T020)
- **사용자 스토리 3 (P1)**: 8개 작업 (T021-T028)
- **마무리**: 10개 작업 (T029-T038)

**병렬 기회**: 22개 작업이 [P]로 표시되어 병렬 실행 가능

**MVP 범위** (최소 실행 가능 제품):

- 1-Phase 2 (설정 + 기초): 5개 작업
- Phase 3 (사용자 스토리 1): 8개 작업
- **총 MVP**: 13개 작업

**예상 일정**:

- **MVP** (US1만): 1-2일
- **전체 기능** (모든 3개 스토리): 3-4일
- **프로덕션 준비** (마무리 포함): 4-5일

**생성할 주요 파일**:

- `elixir_blog/lib/elixir_blog_web/live/category_stats_live.ex` (새로 생성)
- `elixir_blog/lib/elixir_blog_web/components/category_grid.ex` (새로 생성)
- `elixir_blog/test/elixir_blog_web/live/category_stats_live_test.exs` (새로 생성)
- `elixir_blog/test/e2e/category_stats.spec.ts` (새로 생성)
- `elixir_blog/test/e2e/category_navigation.spec.ts` (새로 생성)

**수정할 주요 파일**:

- `elixir_blog/lib/elixir_blog/blog.ex` (list_tags_with_post_counts/1 추가)
- `elixir_blog/lib/elixir_blog_web/router.ex` (/categories 라우트 추가)
- `elixir_blog/lib/elixir_blog_web/components/header.ex` (카테고리 링크 추가)
- `elixir_blog/test/elixir_blog/blog_test.exs` (단위 테스트 추가)

---

## 구현 준비

모든 작업이 명확한 수락 기준과 함께 정의되었습니다. 다음으로 진행하세요:

1. **검토** 완전성을 위해 이 tasks.md 검토
2. **실행** 테스트 우선 구현을 시작하기 위해 `/speckit.implement` 실행
3. **따르기** 각 작업에 대해 빨간색-녹색-리팩토링 사이클
4. **중지** 체크포인트에서 사용자 스토리를 독립적으로 검증
5. **배포** 사용자 스토리 1 완료 후 MVP

행운을 빕니다! 🚀