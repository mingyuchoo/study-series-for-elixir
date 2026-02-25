defmodule ElixirBlogWeb.CategoryStatsLive do
  use ElixirBlogWeb, :live_view

  alias ElixirBlog.Blog
  alias ElixirBlogWeb.Components.{Header, Footer, CategoryGrid, PostGrid}

  @impl true
  def mount(_params, _session, socket) do
    # Load all tags with post counts (alphabetically sorted)
    categories = Blog.list_tags_with_post_counts(sort: :alphabetical)

    # Load popular posts for top section
    popular_posts = Blog.list_popular_posts(limit: 10)

    {:ok,
     socket
     |> assign(:page_title, "카테고리")
     |> assign(
       :meta_description,
       "모든 카테고리와 포스트 통계를 확인하세요. Elixir, Phoenix, 함수형 프로그래밍 등 다양한 주제별로 포스트를 탐색하세요."
     )
     |> assign(:og_type, "website")
     |> assign(:canonical_url, "http://localhost:4000/categories")
     |> assign(:categories, categories)
     |> assign(:popular_posts, popular_posts)
     |> assign(:current_path, "/categories")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex flex-col">
      <Header.header current_path={@current_path} />

      <main class="flex-1">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <!-- Page Header -->
          <div class="py-12">
            <h1 class="text-4xl font-bold text-gray-900 mb-4">카테고리</h1>
            <p class="text-lg text-gray-600">
              주제별로 포스트를 탐색하고 관심 있는 카테고리를 선택하세요
            </p>
          </div>
          
    <!-- Popular Posts Section -->
          <%= if length(@popular_posts) > 0 do %>
            <PostGrid.post_grid posts={@popular_posts} title="인기 포스트" columns={3} />
          <% else %>
            <div class="py-12">
              <h2 class="text-3xl font-bold text-gray-900 mb-8">인기 포스트</h2>
              <div class="bg-gray-50 rounded-lg p-12 text-center">
                <div class="max-w-md mx-auto">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    class="h-16 w-16 mx-auto text-gray-400 mb-4"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke="currentColor"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
                    />
                  </svg>
                  <h3 class="text-xl font-semibold text-gray-700 mb-2">
                    인기 포스트가 없습니다
                  </h3>
                  <p class="text-gray-600">
                    아직 인기 포스트로 표시된 글이 없습니다. 곧 흥미로운 포스트가 추가될 예정입니다!
                  </p>
                </div>
              </div>
            </div>
          <% end %>
          
    <!-- Category Statistics Grid -->
          <%= if length(@categories) > 0 do %>
            <CategoryGrid.category_grid
              categories={@categories}
              title="카테고리별 포스트"
              columns={3}
            />
          <% else %>
            <div class="py-12">
              <h2 class="text-3xl font-bold text-gray-900 mb-8">카테고리별 포스트</h2>
              <div class="bg-gray-50 rounded-lg p-12 text-center">
                <div class="max-w-md mx-auto">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    class="h-16 w-16 mx-auto text-gray-400 mb-4"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke="currentColor"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M7 7h.01M7 3h5c.512 0 1.024.195 1.414.586l7 7a2 2 0 010 2.828l-7 7a2 2 0 01-2.828 0l-7-7A1.994 1.994 0 013 12V7a4 4 0 014-4z"
                    />
                  </svg>
                  <h3 class="text-xl font-semibold text-gray-700 mb-2">
                    카테고리가 없습니다
                  </h3>
                  <p class="text-gray-600">
                    아직 카테고리가 생성되지 않았습니다. 포스트가 추가되면 카테고리가 표시됩니다.
                  </p>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </main>

      <Footer.footer />
    </div>
    """
  end
end
