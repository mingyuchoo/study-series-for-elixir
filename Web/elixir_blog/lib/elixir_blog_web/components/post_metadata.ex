defmodule ElixirBlogWeb.Components.PostMetadata do
  use Phoenix.Component
  import ElixirBlogWeb.CoreComponents

  attr :post, :map, required: true

  def post_metadata(assigns) do
    ~H"""
    <div class="bg-gray-50 rounded-lg p-6 mb-8">
      <div class="flex flex-wrap items-center gap-4 text-sm text-gray-600">
        <div class="flex items-center gap-2">
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z"
            />
          </svg>
          <span class="font-medium">{@post.author}</span>
        </div>

        <div class="flex items-center gap-2">
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
            />
          </svg>
          <span>{@post.reading_time}분 읽기</span>
        </div>

        <div class="flex items-center gap-2">
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"
            />
          </svg>
          <span>{Calendar.strftime(@post.published_at, "%Y년 %m월 %d일")}</span>
        </div>
      </div>

      <%= if length(@post.tags) > 0 do %>
        <div class="mt-4 flex flex-wrap gap-2">
          <%= for tag <- @post.tags do %>
            <.link
              navigate={"/categories/#{tag.slug}"}
              class="inline-block px-3 py-1 bg-primary/10 text-primary rounded-full text-sm font-medium hover:bg-primary/20 transition-colors"
            >
              #{tag.name}
            </.link>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end
