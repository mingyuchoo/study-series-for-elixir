# 빠른 시작 가이드: 카테고리별 포스트 통계 페이지

**기능**: 카테고리 통계 페이지
**브랜치**: `001-category-stats`
**날짜**: 2025-12-30

## 개요

이 가이드는 개발자가 환경을 빠르게 설정하고 카테고리 통계 기능 구현을 시작할 수 있도록 도와줍니다. 개발을 시작하려면 다음 단계를 따르세요.

---

## 필수 조건

### 필요한 소프트웨어

- **Elixir 1.19+** with OTP 28.2+
- **Node.js 18+** 및 npm (애셋 및 Playwright용)
- **SQLite3** (데이터베이스)
- **Git** (버전 관리)
- **Docker** (선택사항, 컨테이너화된 개발용)

### 설치 확인

```bash
# Elixir 버전 확인
elixir --version
# => Elixir 1.19 (compiled with Erlang/OTP 28)

# Node.js 버전 확인
node --version
# => v18.x.x or higher

# SQLite 확인
sqlite3 --version
# => 3.x.x

# Docker 확인 (선택사항)
docker --version
```

---

## 초기 설정

### 1. 저장소 복제 및 기능 브랜치 체크아웃

```bash
# 저장소 복제 (아직 복제하지 않은 경우)
git clone <repository-url>
cd elixir-spec-kit-project

# 기능 브랜치 체크아웃
git checkout 001-category-stats

# 브랜치 확인
git branch
# => * 001-category-stats
```

### 2. 의존성 설치

```bash
# Elixir 프로젝트로 이동
cd elixir_blog

# Elixir 의존성 설치
mix deps.get

# 의존성 컴파일
mix deps.compile

# Node.js 의존성 설치 (애셋용)
cd assets
npm install
cd ..

# Playwright 브라우저 설치 (E2E 테스트용)
cd test/e2e
npx playwright install
cd ../..
```

### 3. 데이터베이스 설정

```bash
# 데이터베이스 생성 (존재하지 않는 경우)
mix ecto.create

# 마이그레이션 실행
mix ecto.migrate

# 테스트 데이터로 데이터베이스 시드
mix run priv/repo/seeds.exs

# 데이터베이스 확인
sqlite3 priv/repo/elixir_blog_dev.db ".tables"
# => posts  posts_tags  schema_migrations  subscriptions  tags
```

### 4. 기존 구현 확인

```bash
# Phoenix 서버 시작
mix phx.server

# 브라우저에서 http://localhost:4000 열기
# 홈페이지 로드 확인
# 기존 카테고리 페이지 작동 확인 (/categories/elixir)
```

---

## 개발 워크플로우

### 이 기능의 파일 구조

```text
specs/001-category-stats/          # 기능 문서
├── spec.md                         # ✅ 사용자 스토리 및 요구사항
├── plan.md                         # ✅ 구현 계획
├── research.md                     # ✅ 아키텍처 결정
├── data-model.md                   # ✅ 엔티티 정의
├── quickstart.md                   # ✅ 이 파일
└── contracts/
    └── blog_context.md             # ✅ API 계약

elixir_blog/lib/                    # 구현 파일
├── elixir_blog/
│   └── blog.ex                     # ⏳ list_tags_with_post_counts/1 추가
└── elixir_blog_web/
    ├── live/
    │   └── category_stats_live.ex  # ⏳ 새로 생성: 개요 페이지
    ├── components/
    │   ├── header.ex               # ⏳ 확장: 카테고리 링크 추가
    │   └── category_grid.ex        # ⏳ 새로 생성: 카테고리 통계 그리드
    └── router.ex                   # ⏳ /categories 라우트 추가

elixir_blog/test/                   # 테스트 파일
├── elixir_blog/
│   └── blog_test.exs               # ⏳ list_tags_with_post_counts 테스트 추가
├── elixir_blog_web/live/
│   └── category_stats_live_test.exs # ⏳ 새로 생성: LiveView 테스트
└── e2e/
    ├── category_stats.spec.ts      # ⏳ 새로 생성: 통계 페이지 E2E 테스트
    └── category_navigation.spec.ts # ⏳ 새로 생성: 카테고리 네비게이션 E2E 테스트
```

**범례**: ✅ 완료 | ⏳ 구현 예정

---

## 구현 단계 (테스트 우선 접근법)

### 1단계: Blog Context 함수

#### 1.1단계: 실패하는 단위 테스트 작성

```bash
# test/elixir_blog/blog_test.exs 편집
# list_tags_with_post_counts/1에 대한 테스트 케이스 추가 (contracts/blog_context.md 참조)
```

**테스트 예시**:

```elixir
describe "list_tags_with_post_counts/1" do
  test "returns tags with aggregated post counts" do
    tag1 = insert(:tag, name: "Elixir")
    tag2 = insert(:tag, name: "Phoenix")
    insert(:post, tags: [tag1])
    insert(:post, tags: [tag1])

    result = Blog.list_tags_with_post_counts()

    assert [
      %{name: "Elixir", slug: "elixir", post_count: 2},
      %{name: "Phoenix", slug: "phoenix", post_count: 0}
    ] = result
  end
end
```

#### 1.2단계: 테스트 실행 (실패해야 함)

```bash
# Blog context 테스트 실행
mix test test/elixir_blog/blog_test.exs

# 예상 결과: ** (UndefinedFunctionError) function Blog.list_tags_with_post_counts/1 is undefined
```

#### 1.3단계: 함수 구현

```bash
# lib/elixir_blog/blog.ex 편집
# list_tags_with_post_counts/1 함수 추가 (구현은 contracts/blog_context.md 참조)
```

#### 1.4단계: 테스트 실행 (통과해야 함)

```bash
mix test test/elixir_blog/blog_test.exs
# 예상 결과: 모든 테스트 통과 (녹색)
```

---

### 2단계: CategoryStatsLive 모듈

#### 2.1단계: 실패하는 LiveView 테스트 작성

```bash
# test/elixir_blog_web/live/category_stats_live_test.exs 생성
```

**테스트 예시**:

```elixir
defmodule ElixirBlogWeb.CategoryStatsLiveTest do
  use ElixirBlogWeb.ConnCase
  import Phoenix.LiveViewTest

  describe "mount" do
    test "displays category statistics", %{conn: conn} do
      tag = insert(:tag, name: "Elixir")
      insert_list(5, :post, tags: [tag])

      {:ok, view, html} = live(conn, "/categories")

      assert html =~ "Elixir"
      assert html =~ "5"  # 포스트 수
    end
  end
end
```

#### 2.2단계: 테스트 실행 (실패해야 함)

```bash
mix test test/elixir_blog_web/live/category_stats_live_test.exs
# 예상 결과: 라우트를 찾을 수 없거나 모듈이 정의되지 않음
```

#### 2.3단계: 라우트 추가

```bash
# lib/elixir_blog_web/router.ex 편집
# 추가: live "/categories", CategoryStatsLive
```

#### 2.4단계: LiveView 모듈 구현

```bash
# lib/elixir_blog_web/live/category_stats_live.ex 생성
# mount/3 및 render/1 구현 (contracts/blog_context.md 참조)
```

#### 2.5단계: 테스트 실행 (통과해야 함)

```bash
mix test test/elixir_blog_web/live/category_stats_live_test.exs
```

---

### 3단계: CategoryGrid 컴포넌트

#### 3.1단계: 컴포넌트 생성

```bash
# lib/elixir_blog_web/components/category_grid.ex 생성
```

**컴포넌트 스켈레톤**:

```elixir
defmodule ElixirBlogWeb.Components.CategoryGrid do
  use Phoenix.Component
  import ElixirBlogWeb.CoreComponents

  attr :categories, :list, required: true
  attr :title, :string, default: nil
  attr :columns, :integer, default: 3

  def category_grid(assigns) do
    ~H"""
    <div class="py-12">
      <%= if @title do %>
        <h2 class="text-3xl font-bold text-gray-900 mb-8">{@title}</h2>
      <% end %>

      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        <%= for category <- @categories do %>
          <.link navigate={"/categories/#{category.slug}"} class="group">
            <div class="bg-white rounded-lg shadow-md p-6 hover:shadow-xl transition-shadow">
              <h3 class="text-xl font-bold text-gray-900 mb-2">
                {category.name}
              </h3>
              <p class="text-3xl font-bold text-primary-600">
                {category.post_count}
              </p>
              <p class="text-sm text-gray-500">
                개의 포스트
              </p>
            </div>
          </.link>
        <% end %>
      </div>
    </div>
    """
  end
end
```

#### 3.2단계: CategoryStatsLive에 통합

```bash
# lib/elixir_blog_web/live/category_stats_live.ex 편집
# CategoryGrid 임포트 및 render 함수에서 사용
```

---

### 4단계: Playwright를 사용한 E2E 테스트

#### 4.1단계: E2E 테스트 작성

```bash
# test/e2e/category_stats.spec.ts 생성
```

**테스트 예시**:

```typescript
import { test, expect } from '@playwright/test';

test.describe('카테고리 통계 페이지', () => {
  test('카테고리 통계 개요를 표시한다', async ({ page }) => {
    await page.goto('http://localhost:4000/categories');

    // 페이지 제목 확인
    await expect(page.locator('h1')).toContainText('카테고리');

    // 카테고리 그리드 표시 확인
    const categoryCards = page.locator('[data-category-card]');
    await expect(categoryCards).toHaveCount.greaterThan(0);

    // 포스트 수 표시 확인
    await expect(page.locator('[data-post-count]').first()).toBeVisible();
  });

  test('클릭 시 카테고리 상세 페이지로 이동한다', async ({ page }) => {
    await page.goto('http://localhost:4000/categories');

    // 첫 번째 카테고리 클릭
    await page.locator('[data-category-card]').first().click();

    // 카테고리 상세 페이지로 이동 확인
    await expect(page.url()).toContain('/categories/');
    await expect(page.locator('h1')).toBeVisible();
  });
});
```

#### 4.2단계: E2E 테스트 실행

```bash
# 백그라운드에서 Phoenix 서버 시작
mix phx.server &

# Playwright 테스트 실행
cd test/e2e
npx playwright test category_stats.spec.ts

# 서버 중지
pkill -f "mix phx.server"
```

---

## 테스트 명령어

### 모든 테스트 실행

```bash
# 단위 테스트
mix test

# 특정 테스트 파일
mix test test/elixir_blog/blog_test.exs

# LiveView 테스트
mix test test/elixir_blog_web/live/

# E2E 테스트
cd test/e2e
npx playwright test
cd ../..
```

### 테스트 커버리지

```bash
# 커버리지 리포트 생성
mix test --cover

# 커버리지 HTML 리포트 보기
open cover/excoveralls.html
```

---

## 개발 서버

### 서버 시작

```bash
# 표준 개발 모드
mix phx.server

# 디버거와 함께
iex -S mix phx.server

# 접속: http://localhost:4000
```

### 라이브 리로드

Phoenix는 코드 변경사항을 자동으로 리로드합니다:

- **Elixir 파일**: 저장 시 자동 재컴파일
- **템플릿 (HEEx)**: 브라우저에서 라이브 리로드
- **CSS/JS**: esbuild/Tailwind를 통한 워치 모드

---

## Docker 개발 (선택사항)

### Docker Compose 사용

```bash
# 개발 환경 시작
docker-compose up dev

# 접속: http://localhost:4000

# 컨테이너에서 테스트 실행
docker-compose run dev mix test

# 컨테이너 중지
docker-compose down
```

---

## 일반적인 문제 및 해결방법

### 문제: 데이터베이스를 찾을 수 없음

**해결방법**:

```bash
# 데이터베이스 재생성
mix ecto.drop
mix ecto.create
mix ecto.migrate
mix run priv/repo/seeds.exs
```

### 문제: 포트 4000이 이미 사용 중

**해결방법**:

```bash
# 기존 Phoenix 서버 종료
pkill -f "mix phx.server"

# 또는 다른 포트 사용
PORT=4001 mix phx.server
```

### 문제: LiveView가 업데이트되지 않음

**해결방법**:

```bash
# 빌드 아티팩트 정리
mix clean
mix deps.clean --all
mix deps.get
mix compile
```

### 문제: Playwright 테스트에서 브라우저를 찾을 수 없음

**해결방법**:

```bash
# Playwright 브라우저 재설치
cd test/e2e
npx playwright install --with-deps
```

---

## 코드 품질 검사

### 코드 포맷팅

```bash
# 포맷팅 확인
mix format --check-formatted

# 모든 파일 자동 포맷팅
mix format
```

### 린터 실행 (Credo)

```bash
# Credo가 설정된 경우
mix credo --strict
```

### 타입 검사 (Dialyzer)

```bash
# PLT 파일 생성 (최초 1회만)
mix dialyzer --plt

# 타입 검사 실행
mix dialyzer
```

---

## 다음 단계

1. ✅ **명세 검토**: 사용자 스토리 및 수락 기준을 위해 `spec.md` 읽기
2. ✅ **계획 검토**: 아키텍처 개요를 위해 `plan.md` 읽기
3. ✅ **연구 검토**: 기술적 결정을 위해 `research.md` 읽기
4. ✅ **계약 검토**: API 정의를 위해 `contracts/blog_context.md` 읽기
5. ⏳ **작업 생성**: `/speckit.tasks` 실행하여 상세한 작업 분석 생성
6. ⏳ **작업 구현**: 각 작업에 대해 테스트 우선 접근법 따르기
7. ⏳ **E2E 테스트 실행**: 엔드투엔드 사용자 시나리오 검증
8. ⏳ **PR 생성**: 완료 시 코드 리뷰를 위해 제출

---

## 유용한 리소스

### 프로젝트 문서

- **CLAUDE.md**: 프로젝트 코딩 가이드라인 및 표준
- **.specify/memory/constitution.md**: 개발 원칙 및 워크플로우
- **README.md**: 일반적인 프로젝트 설정 및 개요

### Phoenix 문서

- [Phoenix LiveView 가이드](https://hexdocs.pm/phoenix_live_view/)
- [Phoenix 라우팅](https://hexdocs.pm/phoenix/routing.html)
- [Ecto 쿼리 API](https://hexdocs.pm/ecto/Ecto.Query.html)

### 테스트 리소스

- [ExUnit 문서](https://hexdocs.pm/ex_unit/)
- [Playwright 문서](https://playwright.dev/docs/intro)
- [Phoenix LiveView 테스팅](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveViewTest.html)

---

## 지원

### 도움 받기

1. **문서 읽기**: 상세한 명세를 위해 `specs/001-category-stats/` 디렉토리 확인
2. **기존 코드 검토**: 유사한 기능 연구 (HomeLive, CategoryLive)
3. **테스트 실행**: 실패하는 테스트는 종종 요구사항을 드러냄
4. **Constitution 확인**: 워크플로우 가이드를 위해 `.specify/memory/constitution.md` 확인

### 문제 보고

문제가 발생하면:

1. 필수 조건이 올바르게 설치되었는지 확인
2. Git 브랜치가 `001-category-stats`인지 확인
3. `mix deps.get`을 실행하여 의존성이 최신인지 확인
4. Phoenix 로그에서 오류 메시지 검토 (`_build/dev/lib/.../ebin`)

---

## 요약

**빠른 설정 체크리스트**:

- [ ] Elixir 1.19+, Node.js 18+, SQLite3 설치
- [ ] `001-category-stats` 브랜치 체크아웃
- [ ] `mix setup` 실행 (또는 `mix deps.get && mix ecto.setup`)
- [ ] Playwright 설치: `cd test/e2e && npx playwright install`
- [ ] 서버 시작: `mix phx.server`
- [ ] 홈페이지 로드 확인: <http://localhost:4000>

**개발 워크플로우**:

1. spec/plan/research 문서 읽기
2. 실패하는 테스트 작성 (빨간색)
3. 최소한의 코드 구현 (녹색)
4. 품질을 위한 리팩토링 (리팩토링)
5. 검증을 위한 E2E 테스트 실행
6. 테스트가 통과하면 커밋

**시작 준비**: 위의 1-4단계 구현 단계를 따르거나 상세한 작업 분석을 위해 `/speckit.tasks`로 진행하세요! 🚀
