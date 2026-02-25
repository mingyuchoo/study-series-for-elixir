defmodule ElixirBlogWeb.CategoryLive do
  use ElixirBlogWeb, :live_view

  alias ElixirBlog.Blog
  alias ElixirBlogWeb.Components.{Header, Footer, CategorySidebar}
  import ElixirBlogWeb.Components.PostGrid

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case Blog.get_tag_by_slug(slug) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "카테고리를 찾을 수 없습니다.")
         |> redirect(to: ~p"/")}

      tag ->
        # Load posts filtered by this category
        filtered_posts = Blog.list_posts_by_category(slug, limit: 50)

        # Load all tags for sidebar
        all_tags = Blog.list_tags()

        {:ok,
         socket
         |> assign(:page_title, "#{tag.name} 포스트")
         |> assign(
           :meta_description,
           "#{tag.name} 카테고리의 모든 포스트를 확인하세요. #{length(filtered_posts)}개의 글이 있습니다."
         )
         |> assign(:og_type, "website")
         |> assign(:canonical_url, "http://localhost:4000/categories/#{slug}")
         |> assign(:tag, tag)
         |> assign(:filtered_posts, filtered_posts)
         |> assign(:all_tags, all_tags)
         |> assign(:current_path, "/categories/#{slug}")}
    end
  end

  @impl true
  def handle_event("change_category", %{"slug" => slug}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/categories/#{slug}")}
  end

  @impl true
  def handle_event("clear_filter", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex flex-col bg-gray-50">
      <Header.header current_path={@current_path} />
      
    <!-- Hero Section with Category Title -->
      <div class="bg-gradient-to-r from-primary-600 to-blue-600 text-white py-16">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div class="max-w-3xl">
            <h1 class="text-4xl md:text-5xl font-bold mb-4">
              {@tag.name}
            </h1>
            <p class="text-xl text-gray-100">
              {length(@filtered_posts)}개의 포스트
            </p>
          </div>
        </div>
      </div>
      
    <!-- Main Content -->
      <main class="flex-1">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
          <div class="grid grid-cols-1 lg:grid-cols-4 gap-8">
            <!-- Main Content (3 columns on large screens) -->
            <div class="lg:col-span-3">
              <%= if length(@filtered_posts) > 0 do %>
                <!-- Filtered Posts Grid -->
                <div class="mb-12">
                  <h2 class="text-2xl font-bold text-gray-900 mb-6">
                    {@tag.name} 카테고리의 모든 포스트
                  </h2>
                  <.post_grid posts={@filtered_posts} />
                </div>
              <% else %>
                <!-- No Posts Found -->
                <div class="text-center py-12">
                  <svg
                    class="mx-auto h-12 w-12 text-gray-400"
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
                  <h3 class="mt-2 text-sm font-medium text-gray-900">포스트 없음</h3>
                  <p class="mt-1 text-sm text-gray-500">
                    이 카테고리에는 아직 포스트가 없습니다.
                  </p>
                  <div class="mt-6">
                    <.link
                      navigate={~p"/"}
                      class="inline-flex items-center px-4 py-2 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-primary hover:bg-primary/90"
                    >
                      홈으로 돌아가기
                    </.link>
                  </div>
                </div>
              <% end %>
            </div>
            
    <!-- Sidebar (1 column on large screens) -->
            <div class="lg:col-span-1">
              <div phx-update="ignore" id="category-sidebar-static">
                <CategorySidebar.category_sidebar
                  tags={@all_tags}
                  current_tag_slug={@tag.slug}
                />
              </div>
            </div>
          </div>
        </div>
      </main>

      <Footer.footer />
    </div>
    """
  end
end
