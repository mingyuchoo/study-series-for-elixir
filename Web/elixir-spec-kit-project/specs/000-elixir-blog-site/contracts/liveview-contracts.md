# LiveView 계약: Elixir 블로그 사이트

**브랜치**: `001-korean-blog-site` | **날짜**: 2025-12-29
**목적**: LiveView 페이지 계약, 컴포넌트 인터페이스, 이벤트 처리 정의

## 개요

Phoenix LiveView는 UI 상호작용이 서버 측 이벤트를 트리거하는 서버 주도 모델을 사용합니다. 이 문서는 모든 LiveView 페이지와 컴포넌트의 계약을 정의합니다.

---

## LiveView 페이지

### 1. HomeLive

**목적**: 캐러셀, 인기 포스트, 카테고리별 포스트, 이메일 구독을 표시하는 홈페이지

**라우트**: `/`

**마운트 매개변수**:

- 없음 (공개 페이지)

**Assigns** (LiveView 상태):

```elixir
%{
  carousel_posts: [Post],      # 캐러셀용 인기 포스트 (is_popular=true)
  carousel_index: integer,      # 현재 캐러셀 슬라이드 인덱스
  popular_posts: [Post],        # 인기 포스트 그리드
  categorized_posts: %{         # 카테고리별로 그룹화된 포스트
    category_slug => [Post]
  },
  subscription_changeset: Changeset, # 이메일 구독 폼 changeset
  subscription_status: atom     # :idle | :success | :error | :duplicate
}
```

**이벤트**:

| 이벤트 | 매개변수 | 설명 | 응답 |
| ----- | --------- | ----------- | -------- |
| `carousel_next` | `%{}` | 다음 캐러셀 슬라이드로 이동 | `carousel_index` 업데이트, 캐러셀 재렌더링 |
| `carousel_prev` | `%{}` | 이전 캐러셀 슬라이드로 이동 | `carousel_index` 업데이트, 캐러셀 재렌더링 |
| `carousel_goto` | `%{"index" => integer}` | 특정 캐러셀 슬라이드로 점프 | `carousel_index` 업데이트, 캐러셀 재렌더링 |
| `subscribe` | `%{"email" => string}` | 이메일 구독 제출 | 검증, 삽입, `subscription_status` 업데이트 |
| `filter_category` | `%{"category" => string}` | 카테고리별 포스트 필터링 | CategoryLive로 이동 또는 assigns 업데이트 |

**컴포넌트 사용**:

- `HeaderComponent` (네비게이션)
- `FooterComponent` (푸터)
- `CarouselComponent` (히어로 캐러셀)
- `PostGridComponent` (인기 포스트, 카테고리별 포스트)
- `SubscriptionFormComponent` (이메일 CTA)

**생명주기**:

1. `mount/3`: 캐러셀 포스트, 인기 포스트, 카테고리별 포스트 로드
2. 자동 진행 타이머: 5초마다 `Process.send_after(self(), :carousel_advance, 5000)`
3. `handle_info(:carousel_advance, socket)`: 캐러셀 자동 진행

---

### 2. PostLive

**목적**: 메타데이터, 콘텐츠, 목차와 함께 개별 블로그 포스트 표시

**라우트**: `/posts/:slug`

**마운트 매개변수**:

- `slug`: URL의 포스트 slug

**Assigns**:

```elixir
%{
  post: Post,                   # 미리 로드된 태그가 있는 포스트
  content_html: string,         # 렌더링된 마크다운 HTML
  toc: [TocEntry],              # 목차 [{level, title, id}]
  related_posts: [Post]         # 유사한 태그를 가진 포스트 (선택사항)
}
```

**이벤트**:

| 이벤트 | 매개변수 | 설명 | 응답 |
| ----- | --------- | ----------- | -------- |
| `scroll_to_section` | `%{"id" => string}` | 목차 섹션으로 스크롤 | 클라이언트 JavaScript로 이벤트 푸시 |
| `tag_clicked` | `%{"tag_slug" => string}` | 카테고리 뷰로 이동 | CategoryLive로 리다이렉트 |

**컴포넌트 사용**:

- `HeaderComponent` (네비게이션)
- `FooterComponent` (푸터)
- `TocComponent` (목차)
- `PostMetadataComponent` (저자, 태그, 읽기 시간)
- `PostContentComponent` (렌더링된 마크다운)

**생명주기**:

1. `mount/3`: slug로 포스트 로드, 마크다운 파싱, 목차 생성
2. 포스트를 찾을 수 없으면 404 처리
3. 적절한 Elixir UTF-8 인코딩으로 콘텐츠 렌더링

---

### 3. CategoryLive

**목적**: 카테고리/태그별로 필터링된 포스트 표시

**라우트**: `/categories/:slug`

**마운트 매개변수**:

- `slug`: URL의 카테고리/태그 slug

**Assigns**:

```elixir
%{
  category: Tag,                # 현재 카테고리/태그
  posts: [Post],                # 이 태그를 가진 포스트
  all_categories: [Tag]         # 모든 사용 가능한 카테고리 (사이드바용)
}
```

**이벤트**:

| 이벤트 | 매개변수 | 설명 | 응답 |
| ----- | --------- | ----------- | -------- |
| `change_category` | `%{"slug" => string}` | 다른 카테고리로 전환 | 새 카테고리로 이동 또는 assigns 업데이트 |
| `clear_filter` | `%{}` | 모든 포스트로 돌아가기 | HomeLive로 이동 |

**컴포넌트 사용**:

- `HeaderComponent` (네비게이션)
- `FooterComponent` (푸터)
- `PostGridComponent` (필터링된 포스트)
- `CategorySidebarComponent` (카테고리 네비게이션)

**생명주기**:

1. `mount/3`: 카테고리 로드, 필터링된 포스트 로드, 모든 카테고리 로드
2. 카테고리를 찾을 수 없으면 404 처리

---

## LiveView Components

### 1. HeaderComponent

**Purpose**: Site-wide navigation header

**Attributes**:

```elixir
attr :current_path, :string, required: true  # For active link highlighting
```

**Render**:

- Logo/site name with link to `/`
- Navigation links: Home, Categories (dropdown), About (optional)
- All text in Korean via Gettext

**Events**: None (uses `phx-click` with navigation)

---

### 2. FooterComponent

**Purpose**: Site-wide footer with additional links and information

**Attributes**:

```elixir
attr :show_subscription, :boolean, default: false  # Show mini subscription form
```

**Render**:

- Copyright notice
- Navigation links
- Social media links (optional)
- All text in Korean

**Events**: None

---

### 3. CarouselComponent

**Purpose**: Auto-advancing hero carousel for popular posts

**Attributes**:

```elixir
attr :posts, :list, required: true       # Popular posts for carousel
attr :current_index, :integer, default: 0 # Current slide index
```

**Events**:

| Event | Parameters | Description |
| ----- | --------- | ----------- |
| `next` | `%{}` | Move to next slide |
| `prev` | `%{}` | Move to previous slide |
| `goto` | `%{"index" => integer}` | Jump to specific slide |

**Slots**: None

**JavaScript Hooks**:

- `CarouselHook`: Manages CSS transitions, pause on hover

**Render**:

- Current slide with thumbnail, title, summary
- Navigation controls (prev/next buttons)
- Indicators (dots) for slide position
- Auto-advance via parent LiveView timer

---

### 4. PostGridComponent

**Purpose**: Reusable grid layout for displaying multiple posts

**Attributes**:

```elixir
attr :posts, :list, required: true          # Posts to display
attr :title, :string, default: nil          # Section title (Korean)
attr :columns, :integer, default: 3         # Grid columns (responsive)
attr :show_excerpt, :boolean, default: true # Show post summary
```

**Slots**:

- `@inner_block`: Optional custom content between posts

**Render**:

- Grid of post cards
- Each card: thumbnail, title, author, reading time, summary (optional)
- Click card to navigate to PostLive

**Events**: None (uses `phx-click` with navigation)

---

### 5. TocComponent

**Purpose**: Table of Contents for blog post navigation

**Attributes**:

```elixir
attr :toc, :list, required: true  # [{level, title, id}]
```

**Events**:

| Event | Parameters | Description |
| ----- | --------- | ----------- |
| `scroll_to` | `%{"id" => string}` | Trigger scroll to section |

**JavaScript Hooks**:

- `TocScrollHook`: Smooth scroll to section, highlight active section

**Render**:

- Nested list of headings (H2, H3)
- Clickable links with anchor IDs
- Sticky positioning (optional)

---

### 6. PostMetadataComponent

**Purpose**: Display post metadata (author, tags, reading time)

**Attributes**:

```elixir
attr :author, :string, required: true
attr :tags, :list, required: true           # [Tag]
attr :reading_time, :integer, required: true
attr :published_at, :datetime, required: true
```

**Events**:

| Event | Parameters | Description |
| ----- | --------- | ----------- |
| `tag_clicked` | `%{"tag_slug" => string}` | Navigate to category |

**Render**:

- Author name
- Clickable tag badges
- Reading time estimate
- Publication date

---

### 7. SubscriptionFormComponent

**Purpose**: Email subscription form with validation

**Attributes**:

```elixir
attr :changeset, Changeset, required: true
attr :status, :atom, default: :idle  # :idle | :success | :error | :duplicate
```

**Events**:

| Event | Parameters | Description |
| ----- | --------- | ----------- |
| `validate` | `%{"subscription" => %{"email" => string}}` | Real-time validation |
| `submit` | `%{"subscription" => %{"email" => string}}` | Submit subscription |

**Render**:

- Email input field
- Submit button
- Status messages (success, error, duplicate) in Korean
- Loading state during submission

---

## Event Flow Diagrams

### Email Subscription Flow

```text
User enters email
      ↓
LiveView: validate event
      ↓
Update changeset (client-side validation)
      ↓
User submits form
      ↓
LiveView: submit event
      ↓
Validate changeset
      ↓
   Insert subscription
      ↓
Check result:
  - Success → Update status: :success, show confirmation
  - Duplicate → Update status: :duplicate, show friendly message
  - Error → Update status: :error, show error message
      ↓
Re-render form with status
```

### Carousel Navigation Flow

```text
Auto-advance timer fires (5 seconds)
      ↓
LiveView: handle_info(:carousel_advance)
      ↓
Increment carousel_index (with wraparound)
      ↓
Push JS event to client for transition
      ↓
Re-render carousel component
      ↓
Schedule next advance (send_after)

OR

User clicks next/prev button
      ↓
LiveView: carousel_next/prev event
      ↓
Update carousel_index
      ↓
Push JS event to client for transition
      ↓
Re-render carousel component
```

### Category Filtering Flow

```text
User clicks category label
      ↓
LiveView: filter_category event
      ↓
Navigate to CategoryLive with slug
      ↓
CategoryLive mounts with category slug
      ↓
Query posts by tag
      ↓
Render filtered PostGrid
```

---

## Data Loading Patterns

### Homepage (HomeLive)

```elixir
def mount(_params, _session, socket) do
  carousel_posts = Blog.list_popular_posts(limit: 5)
  popular_posts = Blog.list_popular_posts(limit: 12)
  categorized_posts = Blog.list_posts_by_category(limit_per_category: 8)

  {:ok,
   socket
   |> assign(:carousel_posts, carousel_posts)
   |> assign(:carousel_index, 0)
   |> assign(:popular_posts, popular_posts)
   |> assign(:categorized_posts, categorized_posts)
   |> assign(:subscription_changeset, Blog.change_subscription(%Subscription{}))
   |> assign(:subscription_status, :idle)
   |> schedule_carousel_advance()}
end

defp schedule_carousel_advance(socket) do
  Process.send_after(self(), :carousel_advance, 5000)
  socket
end
```

### Post Detail (PostLive)

```elixir
def mount(%{"slug" => slug}, _session, socket) do
  case Blog.get_post_by_slug(slug) do
    nil ->
      {:ok,
       socket
       |> put_flash(:error, "게시글을 찾을 수 없습니다.")
       |> redirect(to: "/")}

    post ->
      content_html = MarkdownParser.parse(post.content_path)
      toc = MarkdownParser.generate_toc(post.content_path)

      {:ok,
       socket
       |> assign(:post, post)
       |> assign(:content_html, content_html)
       |> assign(:toc, toc)}
  end
end
```

---

## Form Validation Contracts

### Email Subscription Form

**Changeset Validation**:

```elixir
def changeset(subscription, attrs) do
  subscription
  |> cast(attrs, [:email])
  |> validate_required([:email], message: "이메일을 입력해주세요.")
  |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/,
      message: "올바른 이메일 형식이 아닙니다.")
  |> validate_length(:email, max: 255)
  |> unique_constraint(:email,
      message: "이미 구독 중인 이메일입니다.")
end
```

**Client-side Validation** (LiveView):

```elixir
def handle_event("validate", %{"subscription" => params}, socket) do
  changeset =
    %Subscription{}
    |> Blog.change_subscription(params)
    |> Map.put(:action, :validate)

  {:noreply, assign(socket, :subscription_changeset, changeset)}
end
```

**Server-side Submission**:

```elixir
def handle_event("submit", %{"subscription" => params}, socket) do
  case Blog.create_subscription(params) do
    {:ok, _subscription} ->
      {:noreply,
       socket
       |> assign(:subscription_status, :success)
       |> assign(:subscription_changeset, Blog.change_subscription(%Subscription{}))}

    {:error, %Ecto.Changeset{errors: [{:email, {_, [constraint: :unique]}}]}} ->
      {:noreply, assign(socket, :subscription_status, :duplicate)}

    {:error, changeset} ->
      {:noreply,
       socket
       |> assign(:subscription_status, :error)
       |> assign(:subscription_changeset, changeset)}
  end
end
```

---

## URL Routing

### Routes Definition

```elixir
scope "/", KoreanBlogWeb do
  pipe_through :browser

  live "/", HomeLive, :index
  live "/posts/:slug", PostLive, :show
  live "/categories/:slug", CategoryLive, :show
end
```

### URL Patterns

| Path | LiveView | Description |
| ---- | -------- | ----------- |
| `/` | HomeLive | Homepage |
| `/posts/phoenix-liveview-basics` | PostLive | Blog post detail |
| `/categories/elixir` | CategoryLive | Category-filtered view |

---

## JavaScript Interop

### Alpine.js Integration

Used for client-side transitions and interactions that don't require server state.

**Carousel Transitions**:

```javascript
// assets/js/app.js
window.addEventListener("phx:carousel-transition", (e) => {
  const { direction } = e.detail;
  // Trigger CSS transition for smooth slide change
});
```

**ToC Scroll**:

```javascript
window.addEventListener("phx:scroll-to-section", (e) => {
  const { id } = e.detail;
  document.getElementById(id)?.scrollIntoView({ behavior: "smooth" });
});
```

### LiveView Hooks

**CarouselHook** (pause on hover):

```javascript
let CarouselHook = {
  mounted() {
    this.el.addEventListener("mouseenter", () => {
      this.pushEvent("pause_carousel", {});
    });
    this.el.addEventListener("mouseleave", () => {
      this.pushEvent("resume_carousel", {});
    });
  }
};
```

---

## Error Handling

### 404 Post Not Found

```elixir
def mount(%{"slug" => slug}, _session, socket) do
  case Blog.get_post_by_slug(slug) do
    nil ->
      {:ok,
       socket
       |> put_flash(:error, "게시글을 찾을 수 없습니다.")
       |> redirect(to: "/")}

    post ->
      # ... normal flow
  end
end
```

### 404 Category Not Found

```elixir
def mount(%{"slug" => slug}, _session, socket) do
  case Blog.get_tag_by_slug(slug) do
    nil ->
      {:ok,
       socket
       |> put_flash(:error, "카테고리를 찾을 수 없습니다.")
       |> redirect(to: "/")}

    category ->
      # ... normal flow
  end
end
```

---

## Performance Contracts

### LiveView Performance Best Practices

1. **Minimize Assigns**: Only assign data that affects rendering
2. **Selective Re-rendering**: Use `phx-update="ignore"` for static content
3. **Lazy Loading**: Load related posts only when needed
4. **Preloading**: Use Ecto preloads to avoid N+1 queries
5. **Caching**: Cache parsed Markdown in ETS

### Expected Response Times

| Operation | Target | Notes |
| --------- | ------ | ----- |
| Homepage mount | <500ms | Including carousel and grids |
| Post detail mount | <300ms | Including Markdown parsing |
| Category filter | <200ms | Per SC-007 requirement |
| Email subscription | <2s | Per SC-005 requirement |
| Carousel advance | <100ms | Server-side state update |
| ToC navigation | <5s | Per SC-002 requirement (client-side) |

---

## Testing Contracts

### LiveView Testing

**Test mount and initial render**:

```elixir
test "renders homepage with carousel", %{conn: conn} do
  {:ok, view, html} = live(conn, "/")

  assert html =~ "carousel"
  assert has_element?(view, "#carousel")
end
```

**Test events**:

```elixir
test "handles carousel next event", %{conn: conn} do
  {:ok, view, _html} = live(conn, "/")

  assert view |> element("#carousel-next") |> render_click()
  assert has_element?(view, "#carousel[data-index='1']")
end
```

**Test form submission**:

```elixir
test "creates subscription on valid email", %{conn: conn} do
  {:ok, view, _html} = live(conn, "/")

  view
  |> form("#subscription-form", subscription: %{email: "test@example.com"})
  |> render_submit()

  assert has_element?(view, ".subscription-success")
end
```

---

## API Summary

### Public Functions (Blog Context)

```elixir
Blog.list_popular_posts(opts) :: [Post]
Blog.list_posts_by_category(opts) :: %{category_slug => [Post]}
Blog.get_post_by_slug(slug) :: Post | nil
Blog.get_tag_by_slug(slug) :: Tag | nil
Blog.create_subscription(attrs) :: {:ok, Subscription} | {:error, Changeset}
Blog.change_subscription(subscription, attrs) :: Changeset
```

### MarkdownParser Module

```elixir
MarkdownParser.parse(content_path) :: String.t() # HTML
MarkdownParser.generate_toc(content_path) :: [TocEntry]
MarkdownParser.calculate_reading_time(content_path) :: integer
```
