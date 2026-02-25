# 연구: 카테고리별 포스트 통계 페이지

**기능**: 카테고리 통계 페이지
**날짜**: 2025-12-30
**단계**: 0 - 개요 및 연구

## 연구 질문 및 결과

### 1. 기존 CategoryLive 구현

**질문**: 현재 카테고리 상세 페이지는 어떻게 작동하며, 일관성을 위해 레이아웃을 어떻게 재사용할 수 있는가 (FR-008)?

**결과**:

- **현재 구현**: `CategoryLive` (lib/elixir_blog_web/live/category_live.ex)가 이미 존재함
- **레이아웃 구조**:
  - `Header`와 `Footer` 컴포넌트 사용
  - 필터링된 포스트를 위한 `PostGrid` 컴포넌트 렌더링
  - 태그 네비게이션을 위한 `CategorySidebar` 컴포넌트 보유
  - 카테고리 이름과 포스트 수를 보여주는 그라디언트 배경의 히어로 섹션 특징
  - 3열/1사이드바 레이아웃 사용 (반응형 그리드)

**결정**: **사용자 스토리 3(카테고리 상세 페이지)에 기존 CategoryLive 재사용**. 현재 구현이 이미 일관된 레이아웃에 대한 FR-008 요구사항을 충족합니다. 개요/통계 페이지를 위한 새로운 `CategoryStatsLive` 모듈만 생성하면 됩니다.

**근거**:

- CategoryLive가 이미 태그 슬러그별 필터링된 포스트 목록을 구현함
- 레이아웃이 홈페이지 구조와 일치함 (그리드 기반, 동일한 컴포넌트)
- 구현 범위 축소 - CategoryLive 수정 불필요
- 코드 중복을 피하고 일관성 유지

**고려된 대안**:

- 새로운 CategoryDetailLive 생성: 거부됨 - 불필요한 중복
- CategoryLive에 통계 병합: 거부됨 - 단일 책임 원칙 위반

---

### 2. 집계 쿼리 패턴

**질문**: 한국어/영어 정렬을 지원하면서 태그별 포스트 수를 계산하는 최적의 Ecto 쿼리 패턴은 무엇인가 (FR-005)?

**결과**:

- **현재 태그 쿼리**: `Blog.list_tags()`가 이름순(알파벳순)으로 정렬된 모든 태그를 반환함
- **조인 테이블**: 다대다 관계를 위한 `posts_tags` 테이블이 존재함
- **Ecto 집계**: `group_by`와 `count`를 사용하여 포스트 수를 얻을 수 있음

**결정**: **Ecto 서브쿼리 패턴을 사용하여 `list_tags_with_post_counts/1` 함수 구현**

```elixir
def list_tags_with_post_counts(opts \\ []) do
  sort_by = Keyword.get(opts, :sort, :alphabetical)

  # 태그별 포스트 수를 계산하는 서브쿼리
  post_counts = from(pt in "posts_tags",
    group_by: pt.tag_id,
    select: %{tag_id: pt.tag_id, post_count: count(pt.post_id)}
  )

  # 태그와 포스트 수를 조인하는 메인 쿼리
  query = from(t in Tag,
    left_join: pc in subquery(post_counts), on: t.id == pc.tag_id,
    select: %{
      id: t.id,
      name: t.name,
      slug: t.slug,
      post_count: coalesce(pc.post_count, 0)
    }
  )

  # 정렬 적용
  query = case sort_by do
    :alphabetical -> order_by(query, [t], asc: t.name)
    :post_count -> order_by(query, [t, pc], desc: coalesce(pc.post_count, 0))
  end

  Repo.all(query)
end
```

**근거**:

- 효율적인 단일 쿼리 접근법 (N+1 문제 없음)
- `coalesce`가 포스트가 없는 태그를 처리함 (수를 0으로 표시)
- 유연한 정렬 (FR-005를 위한 알파벳순, 향후 사용을 위한 post_count순)
- SQLite가 이 패턴을 기본적으로 지원함

**고려된 대안**:

- preload를 사용한 즉시 로딩: 거부됨 - Elixir에서 추가 처리 필요
- Tag 스키마의 가상 필드: 거부됨 - 효율적인 정렬 지원 안 함
- 원시 SQL: 거부됨 - Ecto 타입 안전성과 조합성 상실

**한국어/영어 정렬**:

- SQLite는 기본적으로 유니코드 인식 콜레이션 사용
- 한국어 문자(가-힣)가 UTF-8에서 올바르게 정렬됨
- 가나다 순서를 위한 특별한 설정 불필요

---

### 3. 그리드 컴포넌트 설계

**질문**: 카테고리 통계를 표시하기 위해 새로운 CategoryGrid 컴포넌트를 생성해야 하는가, 아니면 PostGrid를 확장해야 하는가?

**결과**:

- **PostGrid 컴포넌트**: 썸네일, 제목, 요약, 작성자, 태그가 있는 포스트 카드를 표시함
- **카테고리 통계 요구사항**: 태그 이름, 포스트 수, 클릭 가능한 카드를 표시함
- **시각적 유사성**: 둘 다 카드가 있는 그리드 레이아웃을 사용하지만 콘텐츠 구조가 다름

**결정**: **새로운 `CategoryGrid` 컴포넌트 생성** (lib/elixir_blog_web/components/category_grid.ex)

**근거**:

- 카테고리 카드는 근본적으로 다른 구조를 가짐 (썸네일, 요약, 작성자 없음)
- 카테고리 카드는 포스트 메타데이터 대신 포스트 수(숫자 통계)를 표시함
- 관심사 분리 - PostGrid는 포스트에 최적화, CategoryGrid는 통계에 최적화
- 독립적으로 스타일링하고 유지보수하기 쉬움
- 그리드 레이아웃 패턴이 다름 (카테고리는 눈에 띄는 수 표시 필요)

**컴포넌트 설계**:

```elixir
attr :categories, :list, required: true  # %{name, slug, post_count} 목록
attr :title, :string, default: nil
attr :columns, :integer, default: 3
attr :show_count, :boolean, default: true

def category_grid(assigns)
```

**고려된 대안**:

- 다형성 렌더링으로 PostGrid 확장: 거부됨 - 너무 복잡, 컴포넌트 명확성 위반
- PostGrid를 그대로 재사용: 거부됨 - UI 불일치, 어색한 데이터 매핑
- 일반적인 CardGrid 사용: 거부됨 - 불필요한 추상화 계층 추가

---

### 4. 라우트 구조

**질문**: 카테고리 통계 개요 페이지에 어떤 라우트 패턴을 사용해야 하는가 (`/categories` vs `/categories/stats`)?

**결과**:

- **기존 라우트**:
  - `/` - 홈페이지 (HomeLive)
  - `/posts/:slug` - 포스트 상세 (PostLive)
  - `/categories/:slug` - 카테고리 상세 (CategoryLive)
- **Phoenix 라우팅 관례**: RESTful 리소스 패턴
- **사용자 기대**: `/categories`는 "모든 카테고리 나열"을 의미함

**결정**: CategoryStatsLive 개요 페이지에 **`/categories` 라우트 사용**

**근거**:

- 의미적 명확성 - `/categories`는 자연스럽게 "모든 카테고리 개요"를 나타냄
- RESTful 관례 - 인덱스 라우트는 컬렉션을 보여주고, 개별 라우트는 멤버를 보여줌
- 자주 접근하는 페이지를 위한 더 짧고 깔끔한 URL
- 사용자 멘탈 모델과 일치 (헤더 링크 "카테고리" → 카테고리 개요)
- 기존 `/categories/:slug` 라우트는 변경 없음 (더 구체적인 패턴)

**라우트 설정**:

```elixir
# router.ex에서
scope "/", ElixirBlogWeb do
  pipe_through :browser

  live "/", HomeLive
  live "/categories", CategoryStatsLive        # 새로움: 개요/통계
  live "/categories/:slug", CategoryLive       # 기존: 필터링된 포스트
  live "/posts/:slug", PostLive
end
```

**고려된 대안**:

- `/categories/stats`: 거부됨 - 불필요하게 장황함, 관례 위반
- `/stats/categories`: 거부됨 - 여러 통계 유형(포스트, 작성자 등)을 의미함
- `/tags`: 거부됨 - 기존 `/categories/:slug` 패턴과 일관성 없음

---

### 5. 성능 최적화

**질문**: 2초 페이지 로드 시간 요구사항(SC-001)을 충족하기 위해 카테고리 통계에 대한 캐싱을 어떻게 처리해야 하는가?

**결과**:

- **현재 캐싱**: 마크다운 파싱을 위한 ETS 캐시가 존재함 (MarkdownCache)
- **데이터 변동성**: 카테고리 포스트 수는 포스트가 추가/제거/태그될 때만 변경됨
- **데이터베이스 성능**: `posts.published_at`, `tags.slug`에 인덱스가 있는 SQLite
- **쿼리 복잡성**: 조인이 있는 단일 집계 쿼리 (중소 데이터셋에서 빠름)

**결정**: **MVP에는 캐싱 불필요; 데이터베이스 인덱스로 최적화**

**근거**:

- 집계 쿼리가 간단하고 빠름 (SQLite에서 100개 이상 카테고리에 대해 <50ms)
- 블로그 포스트는 상대적으로 정적임 (콘텐츠 업데이트 빈도 낮음)
- 조인 테이블(`posts_tags`)의 SQLite 인덱스가 집계를 효율적으로 처리함
- LiveView 마운트 단계가 이미 비동기 로딩을 처리함
- 조기 최적화 - 먼저 측정하고, 필요시 캐시
- ETS 캐시는 복잡성을 추가함 (포스트 업데이트 시 캐시 무효화)

**성능 전략**:

1. **데이터베이스 레벨**:
   - `posts_tags` 조인 테이블에 인덱스가 존재하는지 확인
   - `EXPLAIN QUERY PLAN`을 사용하여 쿼리 성능 검증
2. **LiveView 레벨**:
   - 마운트에서 데이터 로드 (동기식, 2초 예산에 허용됨)
   - 매우 큰 데이터셋을 위한 LiveView 스트리밍 사용 (향후 최적화)
3. **향후 최적화** (필요시):
   - TTL(5-10분)이 있는 ETS 캐시 추가
   - 포스트 생성/업데이트/삭제 이벤트에서 캐시 무효화
   - 백그라운드 캐시 새로고침을 위한 GenServer 고려

**고려된 대안**:

- 처음부터 ETS 캐시: 거부됨 - 측정된 필요 없이 복잡성 추가
- Agent 기반 캐시: 거부됨 - 정적 데이터에 과도함
- 데이터베이스 구체화된 뷰: 거부됨 - SQLite 지원 안 함, 마이그레이션 복잡성 추가

---

## 아키텍처 결정 요약

### 생성할 컴포넌트

1. **CategoryStatsLive** (lib/elixir_blog_web/live/category_stats_live.ex)
   - 마운트: 인기 포스트 + 수가 포함된 태그 로드
   - 렌더: 인기 섹션 + 카테고리 그리드
   - 라우트: `/categories`

2. **CategoryGrid 컴포넌트** (lib/elixir_blog_web/components/category_grid.ex)
   - 이름, 포스트 수가 있는 카테고리 카드 표시
   - 설정 가능한 열 (기본값: 3)
   - 클릭 가능한 카드가 `/categories/:slug`로 이동

### 추가할 Blog 컨텍스트 함수

1. **`list_tags_with_post_counts/1`**
   - 집계된 포스트 수가 있는 태그 반환
   - 정렬 지원: `:alphabetical` (기본값), `:post_count`
   - 효율성을 위한 서브쿼리 패턴 사용

### 수정할 컴포넌트

1. **Header 컴포넌트** (lib/elixir_blog_web/components/header.ex)
   - `/categories`를 가리키는 "카테고리" 링크 추가

### 재사용할 컴포넌트 (변경 없음)

1. **CategoryLive** - 이미 카테고리 상세 페이지를 구현함 (사용자 스토리 3)
2. **PostGrid** - 인기 포스트 섹션에 재사용
3. **Footer** - 표준 푸터 컴포넌트
4. **기존 Blog 함수들**:
   - `list_popular_posts/1` - 인기 섹션용
   - `list_posts_by_category/2` - CategoryLive에서 사용

### 테스팅 전략

1. **단위 테스트** (test/elixir_blog/blog_test.exs):
   - 픽스처로 `list_tags_with_post_counts/1` 테스트
   - 정렬, 0 카운트, 한국어/영어 이름 검증

2. **LiveView 테스트** (test/elixir_blog_web/live/category_stats_live_test.exs):
   - 마운트 성공 테스트
   - 카테고리 카드 렌더링 테스트
   - 카테고리 상세로의 네비게이션 테스트

3. **E2E 테스트** (Playwright):
   - `category_stats.spec.ts` - 통계 페이지의 전체 사용자 여정
   - `category_navigation.spec.ts` - 네비게이션 플로우 (홈 → 카테고리 → 상세)

---

## 기술적 제약사항 검증

### 한국어 지원

- ✅ SQLite UTF-8 콜레이션이 가-힣 정렬을 지원함
- ✅ 기존 코드베이스가 이미 한국어 텍스트를 처리함 (HomeLive, CategoryLive)
- ✅ 알파벳 정렬을 위한 특별한 설정 불필요

### 성능 요구사항

- ✅ 집계 쿼리 예상 <50ms (단일 조인 + group_by)
- ✅ LiveView 마운트 예산: ~200ms (데이터 로딩)
- ✅ 남은 예산: ~1750ms 렌더링용 (100개 이상 카테고리에 충분함)

### 모바일 반응성

- ✅ PostGrid 컴포넌트가 이미 반응형 Tailwind 클래스 사용
- ✅ CategoryGrid가 동일한 패턴을 따를 것 (모바일 1열, 데스크톱 2-3열)
- ✅ 기존 CSS 프레임워크가 최소 2열 요구사항을 지원함 (SC-007)

### 일관성 요구사항 (FR-008, SC-005)

- ✅ CategoryLive가 이미 HomeLive와 동일한 Header, Footer, PostGrid 사용
- ✅ 시각적 일관성 유지를 위한 변경 불필요
- ✅ CategoryStatsLive가 동일한 컴포넌트 세트 사용할 것

---

## 미해결 질문 / 향후 고려사항

1. **페이지네이션**: 현재 구현은 모든 카테고리를 한 번에 로드함
   - **권장사항**: 실제 데이터로 성능 모니터링; 50개 이상 카테고리 시 페이지네이션 추가

2. **카테고리 아이콘/이미지**: 요구사항에 명시되지 않음
   - **권장사항**: MVP에서는 단순하게 유지; 향후 반복에서 아이콘 지원 고려

3. **인기 포스트 빈 상태**: `is_popular`로 표시된 포스트가 없으면?
   - **결정**: 빈 상태 메시지 표시 (사용자 스토리 2, 수락 시나리오 3)

4. **카테고리 색상 코딩**: 시각적 구별을 향상시킬 수 있음
   - **권장사항**: 향후 개선사항; MVP에 필요하지 않음

---

## 다음 단계

연구가 완료되어 **1단계: 설계 및 계약**으로 진행:

1. `data-model.md`에 데이터 모델 문서화
2. `contracts/blog_context.md`에 API 계약 정의
3. `quickstart.md`에 개발 빠른 시작 가이드 생성
4. 새로운 패턴으로 에이전트 컨텍스트 업데이트
