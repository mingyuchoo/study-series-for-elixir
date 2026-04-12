defmodule ElixirBlogWeb.HomeLive do
  use ElixirBlogWeb, :live_view

  alias ElixirBlog.Blog
  alias ElixirBlog.Blog.Subscription
  alias ElixirBlogWeb.Components.{Header, Footer, Carousel, PostGrid, SubscriptionForm}

  @impl true
  def mount(_params, _session, socket) do
    # Load carousel posts (popular posts)
    carousel_posts = Blog.list_popular_posts(limit: 5)

    # Load popular posts grid
    popular_posts = Blog.list_popular_posts(limit: 6)

    # Load categorized posts by tag
    categorized_posts = load_categorized_posts()

    # Initialize subscription changeset
    subscription_changeset = Blog.change_subscription(%Subscription{})

    # Schedule carousel auto-advance
    if connected?(socket) do
      schedule_carousel_advance()
    end

    {:ok,
     socket
     |> assign(:page_title, "홈")
     |> assign(
       :meta_description,
       "Phoenix LiveView로 만든 Elixir 기술 블로그. Elixir, Phoenix, 그리고 함수형 프로그래밍에 대한 최신 글을 읽어보세요."
     )
     |> assign(:og_type, "website")
     |> assign(:canonical_url, "http://localhost:4000/")
     |> assign(:carousel_posts, carousel_posts)
     |> assign(:carousel_index, 0)
     |> assign(:popular_posts, popular_posts)
     |> assign(:categorized_posts, categorized_posts)
     |> assign(:subscription_changeset, subscription_changeset)
     |> assign(:subscription_status, nil)
     |> assign(:current_path, "/")}
  end

  @impl true
  def handle_event("carousel_next", _params, socket) do
    new_index = rem(socket.assigns.carousel_index + 1, length(socket.assigns.carousel_posts))
    {:noreply, assign(socket, :carousel_index, new_index)}
  end

  @impl true
  def handle_event("carousel_prev", _params, socket) do
    count = length(socket.assigns.carousel_posts)
    new_index = rem(socket.assigns.carousel_index - 1 + count, count)
    {:noreply, assign(socket, :carousel_index, new_index)}
  end

  @impl true
  def handle_event("carousel_goto", %{"index" => index}, socket) do
    {:noreply, assign(socket, :carousel_index, String.to_integer(index))}
  end

  @impl true
  def handle_event("pause_carousel", _params, socket) do
    # Handle carousel pause (when mouse enters)
    {:noreply, socket}
  end

  @impl true
  def handle_event("resume_carousel", _params, socket) do
    # Handle carousel resume (when mouse leaves)
    {:noreply, socket}
  end

  @impl true
  def handle_event("validate_subscription", %{"subscription" => subscription_params}, socket) do
    changeset =
      %Subscription{}
      |> Blog.change_subscription(subscription_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :subscription_changeset, changeset)}
  end

  @impl true
  def handle_event("subscribe", %{"subscription" => subscription_params}, socket) do
    case Blog.create_subscription(subscription_params) do
      {:ok, _subscription} ->
        {:noreply,
         socket
         |> assign(:subscription_status, :success)
         |> assign(:subscription_changeset, Blog.change_subscription(%Subscription{}))}

      {:error, %Ecto.Changeset{errors: errors} = changeset} ->
        # Check if error is due to duplicate email
        status =
          if Keyword.has_key?(errors, :email) do
            {_, meta} = errors[:email]

            if meta[:constraint] == :unique do
              :duplicate
            else
              :error
            end
          else
            :error
          end

        {:noreply,
         socket
         |> assign(:subscription_status, status)
         |> assign(:subscription_changeset, changeset)}
    end
  end

  @impl true
  def handle_info(:carousel_advance, socket) do
    # Auto-advance carousel
    new_index = rem(socket.assigns.carousel_index + 1, length(socket.assigns.carousel_posts))

    # Schedule next advance
    schedule_carousel_advance()

    {:noreply, assign(socket, :carousel_index, new_index)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex flex-col">
      <Header.header current_path={@current_path} />

      <main class="flex-1">
        <!-- Carousel Hero Section -->
        <%= if length(@carousel_posts) > 0 do %>
          <Carousel.carousel posts={@carousel_posts} current_index={@carousel_index} />
        <% end %>

        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <!-- Popular Posts Grid (static after initial load) -->
          <%= if length(@popular_posts) > 0 do %>
            <div phx-update="ignore" id="popular-posts-static">
              <PostGrid.post_grid posts={@popular_posts} title="인기 포스트" columns={3} />
            </div>
          <% end %>
          
    <!-- Categorized Posts Sections (static after initial load) -->
          <div phx-update="ignore" id="categorized-posts-static">
            <%= for {category_name, posts} <- @categorized_posts do %>
              <%= if length(posts) > 0 do %>
                <PostGrid.post_grid posts={posts} title={category_name} columns={4} />
              <% end %>
            <% end %>
          </div>
        </div>
        
    <!-- Email Subscription Form -->
        <SubscriptionForm.subscription_form
          changeset={@subscription_changeset}
          status={@subscription_status}
        />
      </main>

      <Footer.footer />
    </div>
    """
  end

  # Private helper functions

  defp load_categorized_posts do
    # Get some popular tags and load posts for each
    tags = Blog.list_tags() |> Enum.take(3)

    Enum.map(tags, fn tag ->
      posts = Blog.list_posts_by_category(tag.slug, limit: 4)
      {tag.name, posts}
    end)
  end

  defp schedule_carousel_advance do
    # Auto-advance every 5 seconds
    Process.send_after(self(), :carousel_advance, 5_000)
  end
end
