defmodule ElixirBlogWeb.Components.PostGrid do
  use Phoenix.Component
  import ElixirBlogWeb.CoreComponents

  attr :posts, :list, required: true
  attr :title, :string, default: nil
  attr :columns, :integer, default: 3

  def post_grid(assigns) do
    assigns =
      assign(assigns, :is_category_section, assigns.title != nil and assigns.title != "인기 포스트")

    ~H"""
    <div class="py-12" data-category-section={@is_category_section}>
      <%= if @title do %>
        <h2 class="text-3xl font-bold text-gray-900 mb-8">{@title}</h2>
      <% end %>

      <div class={[
        "grid gap-6",
        case @columns do
          2 -> "grid-cols-1 md:grid-cols-2"
          3 -> "grid-cols-1 md:grid-cols-2 lg:grid-cols-3"
          4 -> "grid-cols-1 md:grid-cols-2 lg:grid-cols-4"
          _ -> "grid-cols-1 md:grid-cols-3"
        end
      ]}>
        <%= for post <- @posts do %>
          <.link navigate={"/posts/#{post.slug}"} class="group">
            <article
              class="bg-white rounded-lg shadow-md overflow-hidden hover:shadow-xl transition-shadow"
              data-post-card
            >
              <!-- Thumbnail -->
              <div class="aspect-video bg-gradient-to-br from-purple-400 to-blue-500 relative overflow-hidden">
                <div class="absolute inset-0 flex items-center justify-center text-white text-lg font-semibold">
                  {String.slice(post.title, 0..20)}
                </div>
              </div>
              
    <!-- Content -->
              <div class="p-6">
                <h3 class="text-xl font-bold text-gray-900 mb-2 group-hover:text-primary-600 transition-colors line-clamp-2">
                  {post.title}
                </h3>

                <p class="text-gray-600 mb-4 line-clamp-3">
                  {post.summary}
                </p>

                <div class="flex items-center justify-between text-sm text-gray-500">
                  <span>{post.author}</span>
                  <span>{post.reading_time}분</span>
                </div>
                
    <!-- Tags -->
                <%= if length(post.tags) > 0 do %>
                  <div class="mt-4 flex flex-wrap gap-2">
                    <%= for tag <- Enum.take(post.tags, 3) do %>
                      <span class="inline-block px-3 py-1 bg-gray-100 text-gray-700 text-xs rounded-full">
                        {tag.name}
                      </span>
                    <% end %>
                  </div>
                <% end %>
              </div>
            </article>
          </.link>
        <% end %>
      </div>
    </div>
    """
  end
end
