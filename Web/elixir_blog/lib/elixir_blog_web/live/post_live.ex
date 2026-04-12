defmodule ElixirBlogWeb.PostLive do
  use ElixirBlogWeb, :live_view
  alias ElixirBlog.Blog
  alias ElixirBlog.Blog.MarkdownParser
  alias ElixirBlogWeb.Components.{Header, Footer}
  import ElixirBlogWeb.Components.Toc
  import ElixirBlogWeb.Components.PostMetadata
  import ElixirBlogWeb.Components.PostContent

  def mount(%{"slug" => slug}, _session, socket) do
    case Blog.get_post_by_slug(slug) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "포스트를 찾을 수 없습니다.")
         |> redirect(to: ~p"/")}

      post ->
        # Read Markdown content from file using absolute path
        content_file_path = Path.join(:code.priv_dir(:elixir_blog), "posts/#{post.content_path}")

        {html_content, headings} =
          case File.read(content_file_path) do
            {:ok, content} ->
              # Parse Markdown content
              case MarkdownParser.parse(content) do
                {:ok, html} ->
                  # Generate table of contents
                  toc = MarkdownParser.generate_toc(content)
                  {html, toc}

                {:error, _errors} ->
                  error_msg = "마크다운 파싱 중 오류가 발생했습니다."
                  {"<p>#{error_msg}</p>", []}
              end

            {:error, reason} ->
              error_msg = "콘텐츠를 불러올 수 없습니다. (#{inspect(reason)})"
              {"<p>#{error_msg}</p>", []}
          end

        {:ok,
         socket
         |> assign(:page_title, post.title)
         |> assign(:meta_description, post.summary)
         |> assign(:og_type, "article")
         |> assign(:og_image, "/images/#{post.thumbnail}")
         |> assign(:canonical_url, "http://localhost:4000/posts/#{slug}")
         |> assign(:post, post)
         |> assign(:html_content, html_content)
         |> assign(:headings, headings)
         |> assign(:current_path, "/posts/#{slug}")}
    end
  end

  def handle_event("scroll_to_section", %{"id" => _id}, socket) do
    # Client-side JavaScript will handle actual scrolling
    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex flex-col bg-gray-50">
      <Header.header current_path={@current_path} />
      
    <!-- Hero Section with Post Title -->
      <div class="bg-gradient-to-r from-primary-600 to-blue-600 text-white py-16">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div class="max-w-3xl">
            <h1 class="text-4xl md:text-5xl font-bold mb-4">
              {@post.title}
            </h1>
            <p class="text-xl text-gray-100">
              {@post.summary}
            </p>
          </div>
        </div>
      </div>
      
    <!-- Main Content -->
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
        <div class="grid grid-cols-1 lg:grid-cols-4 gap-8">
          <!-- Main Article (3 columns on large screens) -->
          <div class="lg:col-span-3">
            <!-- Post Metadata (static after initial load) -->
            <div phx-update="ignore" id="post-metadata-static">
              <.post_metadata post={@post} />
            </div>
            
    <!-- Post Content (static after initial load) -->
            <div phx-update="ignore" id="post-content-static">
              <.post_content html_content={@html_content} />
            </div>
            
    <!-- Back to Home Link -->
            <div class="mt-12 pt-8 border-t border-gray-200">
              <.link
                navigate={~p"/"}
                class="inline-flex items-center text-primary hover:text-primary/80 font-medium"
              >
                <svg
                  class="w-5 h-5 mr-2"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M10 19l-7-7m0 0l7-7m-7 7h18"
                  />
                </svg>
                홈으로 돌아가기
              </.link>
            </div>
          </div>
          
    <!-- Sidebar with Table of Contents (1 column on large screens) -->
          <div class="lg:col-span-1">
            <%= if length(@headings) > 0 do %>
              <.toc headings={@headings} />
            <% end %>
          </div>
        </div>
      </div>

      <Footer.footer />
    </div>
    """
  end
end
