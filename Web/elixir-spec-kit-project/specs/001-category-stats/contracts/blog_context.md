# API Contract: Blog Context Functions

**Module**: `ElixirBlog.Blog`
**Feature**: Category Statistics Page
**Date**: 2025-12-30

## Overview

This document specifies the function contracts for the Blog context that support the category statistics feature. All functions are additions or clarifications to the existing `ElixirBlog.Blog` module.

---

## New Functions

### `list_tags_with_post_counts/1`

Returns all tags with aggregated post counts, optionally sorted.

**Signature**:

```elixir
@spec list_tags_with_post_counts(keyword()) :: [map()]
def list_tags_with_post_counts(opts \\ [])
```

**Parameters**:

- `opts` (keyword list):
  - `:sort` - Sorting strategy (default: `:alphabetical`)
    - `:alphabetical` - Sort by tag name (A-Z, 가-힣)
    - `:post_count` - Sort by post count (descending)

**Returns**:

- List of maps with structure:

  ```elixir
  [
    %{
      id: integer,         # Tag ID
      name: string,        # Tag name (supports Korean/English)
      slug: string,        # URL-friendly slug
      post_count: integer  # Number of posts (0 if none)
    },
    ...
  ]
  ```

**Behavior**:

1. Queries `tags` table with LEFT JOIN on `posts_tags`
2. Groups by tag to count associated posts
3. Uses `COALESCE(COUNT, 0)` to ensure zero counts for tags without posts
4. Sorts according to `:sort` option
5. Returns list ordered by sort criteria

**Examples**:

```elixir
# Get all tags sorted alphabetically (default)
Blog.list_tags_with_post_counts()
# => [%{id: 1, name: "Elixir", slug: "elixir", post_count: 15}, ...]

# Get tags sorted by post count (most popular first)
Blog.list_tags_with_post_counts(sort: :post_count)
# => [%{id: 3, name: "Phoenix", slug: "phoenix", post_count: 42}, ...]

# Empty tags included with zero count
Blog.list_tags_with_post_counts()
# => [..., %{id: 10, name: "GraphQL", slug: "graphql", post_count: 0}, ...]
```

**Edge Cases**:

- **No tags**: Returns `[]`
- **No posts**: All tags have `post_count: 0`
- **Tag without posts**: Included in results with `post_count: 0` (not filtered out)
- **Korean names**: Sorted correctly in 가나다 order (UTF-8 collation)

**Performance**:

- Single SQL query with `GROUP BY` and `LEFT JOIN`
- Expected execution time: <50ms for 100 tags, 1000 posts
- No N+1 queries (single aggregation)

**Implementation Query** (Reference):

```elixir
defp list_tags_with_post_counts(opts) do
  sort_by = Keyword.get(opts, :sort, :alphabetical)

  # Subquery to count posts per tag
  post_counts = from(pt in "posts_tags",
    group_by: pt.tag_id,
    select: %{tag_id: pt.tag_id, post_count: count(pt.post_id)}
  )

  # Main query joining tags with post counts
  query = from(t in Tag,
    left_join: pc in subquery(post_counts), on: t.id == pc.tag_id,
    select: %{
      id: t.id,
      name: t.name,
      slug: t.slug,
      post_count: coalesce(pc.post_count, 0)
    }
  )

  # Apply sorting
  query = case sort_by do
    :alphabetical -> order_by(query, [t], asc: t.name)
    :post_count -> order_by(query, [t, pc], desc: coalesce(pc.post_count, 0))
  end

  Repo.all(query)
end
```

---

## Existing Functions (Reused)

### `list_popular_posts/1`

Returns popular posts for display in the popular section.

**Signature**:

```elixir
@spec list_popular_posts(keyword()) :: [Post.t()]
def list_popular_posts(opts \\ [])
```

**Parameters**:

- `opts` (keyword list):
  - `:limit` - Maximum number of posts (default: 10)

**Returns**:

- List of `%Post{}` structs with preloaded `:tags` association

**Usage in Feature**:

- User Story 2: Popular posts section on CategoryStatsLive
- Query: `Blog.list_popular_posts(limit: 10)`

**Behavior**:

- Filters posts where `is_popular == true`
- Orders by `published_at` descending (most recent first)
- Preloads tags for display
- Limits results to specified count

---

### `list_posts_by_category/2`

Returns posts filtered by category slug for category detail pages.

**Signature**:

```elixir
@spec list_posts_by_category(String.t(), keyword()) :: [Post.t()]
def list_posts_by_category(tag_slug, opts \\ [])
```

**Parameters**:

- `tag_slug` (string) - Category slug to filter by
- `opts` (keyword list):
  - `:limit` - Maximum number of posts (default: 12)

**Returns**:

- List of `%Post{}` structs with preloaded `:tags` association

**Usage in Feature**:

- User Story 3: Category detail page (CategoryLive)
- Already implemented, no changes needed

**Behavior**:

- Joins posts with tags through `posts_tags`
- Filters by `tag.slug == tag_slug`
- Orders by `published_at` descending
- Preloads tags for display

---

### `get_tag_by_slug/1`

Gets a single tag by slug for category detail pages.

**Signature**:

```elixir
@spec get_tag_by_slug(String.t()) :: Tag.t() | nil
def get_tag_by_slug(slug)
```

**Parameters**:

- `slug` (string) - Tag slug to look up

**Returns**:

- `%Tag{}` struct if found
- `nil` if not found

**Usage in Feature**:

- User Story 3: CategoryLive mount to verify tag exists
- Already implemented, no changes needed

---

## LiveView Integration

### CategoryStatsLive

**Module**: `ElixirBlogWeb.CategoryStatsLive`
**Route**: `/categories`

**Mount Function**:

```elixir
@impl true
def mount(_params, _session, socket) do
  # Load all tags with post counts (alphabetically sorted)
  categories = Blog.list_tags_with_post_counts(sort: :alphabetical)

  # Load popular posts for top section
  popular_posts = Blog.list_popular_posts(limit: 10)

  {:ok,
   socket
   |> assign(:page_title, "카테고리")
   |> assign(:meta_description, "모든 카테고리와 포스트 통계를 확인하세요.")
   |> assign(:categories, categories)
   |> assign(:popular_posts, popular_posts)
   |> assign(:current_path, "/categories")}
end
```

**Assigns**:

- `@categories` - List of category statistics maps
- `@popular_posts` - List of popular Post structs
- `@page_title` - SEO page title
- `@meta_description` - SEO description
- `@current_path` - Current route for header highlighting

**Events**: None (static page, no user interactions beyond navigation)

---

### CategoryLive (Existing, No Changes)

**Module**: `ElixirBlogWeb.CategoryLive`
**Route**: `/categories/:slug`

**Mount Function** (Reference):

```elixir
@impl true
def mount(%{"slug" => slug}, _session, socket) do
  case Blog.get_tag_by_slug(slug) do
    nil ->
      {:ok, socket |> put_flash(:error, "카테고리를 찾을 수 없습니다.") |> redirect(to: ~p"/")}
    tag ->
      filtered_posts = Blog.list_posts_by_category(slug, limit: 50)
      all_tags = Blog.list_tags()

      {:ok, socket |> assign(:tag, tag) |> assign(:filtered_posts, filtered_posts) |> assign(:all_tags, all_tags)}
  end
end
```

**Usage**: Already handles User Story 3 (category detail page)

---

## Component Integration

### CategoryGrid Component

**Module**: `ElixirBlogWeb.Components.CategoryGrid`

**Function Signature**:

```elixir
attr :categories, :list, required: true
attr :title, :string, default: nil
attr :columns, :integer, default: 3

def category_grid(assigns)
```

**Input Contract**:

- `categories` - List of maps from `list_tags_with_post_counts/1`:

  ```elixir
  [%{id: integer, name: string, slug: string, post_count: integer}, ...]
  ```

- `title` - Optional section title
- `columns` - Grid columns (1, 2, 3, or 4)

**Output**: Rendered HEEx template with clickable category cards

**Usage**:

```elixir
<CategoryGrid.category_grid
  categories={@categories}
  title="카테고리별 포스트"
  columns={3}
/>
```

---

## Error Handling

### Function-Level Errors

1. **`list_tags_with_post_counts/1`**:
   - **Database error**: Raises `Ecto.QueryError` (caught by Phoenix error boundary)
   - **Invalid sort option**: Ignored, falls back to `:alphabetical`
   - **Empty result**: Returns `[]` (valid state)

2. **`list_popular_posts/1`**:
   - **No popular posts**: Returns `[]` (triggers empty state in UI)
   - **Database error**: Raises `Ecto.QueryError`

3. **`list_posts_by_category/2`**:
   - **Invalid tag_slug**: Returns `[]` (empty category)
   - **Non-existent slug**: Returns `[]`

### LiveView-Level Errors

1. **CategoryStatsLive mount**:
   - **Database unavailable**: Crashes LiveView, shows 500 error page
   - **No categories**: Renders page with empty grids (valid state)

2. **CategoryLive mount**:
   - **Invalid slug**: Redirects to home with flash error (existing behavior)

---

## Testing Contracts

### Unit Tests (test/elixir_blog/blog_test.exs)

**Test Cases for `list_tags_with_post_counts/1`**:

```elixir
describe "list_tags_with_post_counts/1" do
  test "returns all tags with post counts in alphabetical order" do
    tag1 = insert(:tag, name: "Elixir")
    tag2 = insert(:tag, name: "Phoenix")
    post = insert(:post, tags: [tag1, tag1])  # 2 posts for Elixir

    result = Blog.list_tags_with_post_counts()

    assert [%{name: "Elixir", post_count: 2}, %{name: "Phoenix", post_count: 0}] = result
  end

  test "returns tags sorted by post count when requested" do
    tag1 = insert(:tag, name: "Elixir")
    tag2 = insert(:tag, name: "Phoenix")
    insert(:post, tags: [tag2, tag2, tag2])  # 3 posts for Phoenix
    insert(:post, tags: [tag1])              # 1 post for Elixir

    result = Blog.list_tags_with_post_counts(sort: :post_count)

    assert [%{name: "Phoenix", post_count: 3}, %{name: "Elixir", post_count: 1}] = result
  end

  test "includes tags with zero posts" do
    tag = insert(:tag, name: "Empty Tag")

    result = Blog.list_tags_with_post_counts()

    assert [%{name: "Empty Tag", post_count: 0}] = result
  end

  test "handles Korean tag names correctly" do
    tag1 = insert(:tag, name: "엘릭서")
    tag2 = insert(:tag, name: "피닉스")

    result = Blog.list_tags_with_post_counts()

    # Verify Korean alphabetical order (가나다순)
    assert [%{name: "엘릭서"}, %{name: "피닉스"}] = result
  end
end
```

### LiveView Tests (test/elixir_blog_web/live/category_stats_live_test.exs)

**Test Cases for CategoryStatsLive**:

```elixir
describe "CategoryStatsLive mount" do
  test "loads and displays category statistics", %{conn: conn} do
    tag = insert(:tag, name: "Elixir")
    insert_list(5, :post, tags: [tag])

    {:ok, view, html} = live(conn, "/categories")

    assert html =~ "Elixir"
    assert html =~ "5개의 포스트"  # Post count display
  end

  test "displays popular posts section", %{conn: conn} do
    insert(:post, title: "Popular Post", is_popular: true)

    {:ok, view, html} = live(conn, "/categories")

    assert html =~ "Popular Post"
    assert html =~ "인기 포스트"
  end

  test "handles empty categories gracefully", %{conn: conn} do
    # No tags or posts

    {:ok, view, html} = live(conn, "/categories")

    # Should not crash, may show empty state
    refute html =~ "error"
  end
end
```

---

## Performance Contracts

### Query Performance Targets

1. **`list_tags_with_post_counts/1`**:
   - **Target**: <50ms for 100 tags, 1000 posts
   - **Measurement**: Use `Ecto.LogEntry` or `Telemetry` events
   - **Verification**: E2E test with Playwright timing

2. **CategoryStatsLive Mount**:
   - **Target**: <500ms total (2-second budget - SC-001)
   - **Breakdown**:
     - Database queries: <100ms
     - LiveView initialization: <200ms
     - Rendering: <200ms

### Load Testing Requirements

- **Concurrent Users**: 10 users accessing `/categories` simultaneously
- **Expected Behavior**: No degradation, all pages load within 2 seconds
- **Tool**: Playwright parallel tests or `ab` (Apache Bench)

---

## Versioning & Compatibility

**API Version**: 1.0
**Breaking Changes**: None (all additions, no modifications to existing functions)
**Backward Compatibility**: ✅ Fully compatible with existing Blog context API

**Future Enhancements** (Non-Breaking):

- Add `:filter` option to exclude empty categories
- Add `:include_description` option to preload tag descriptions (if schema extended)
- Add `:cache` option to enable ETS caching

---

## Summary

### New Functions

- ✅ `list_tags_with_post_counts/1` - Aggregates post counts per tag

### Reused Functions

- ✅ `list_popular_posts/1` - Fetches popular posts
- ✅ `list_posts_by_category/2` - Filters posts by category
- ✅ `get_tag_by_slug/1` - Looks up tag by slug

### Performance

- ✅ All queries <100ms (within budget)
- ✅ No N+1 queries
- ✅ Single-trip database operations

### Testing

- ✅ Unit tests for new function
- ✅ LiveView integration tests
- ✅ E2E tests with Playwright (User Story validation)
