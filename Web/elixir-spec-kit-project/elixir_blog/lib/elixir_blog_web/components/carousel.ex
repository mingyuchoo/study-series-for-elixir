defmodule ElixirBlogWeb.Components.Carousel do
  use Phoenix.Component
  import ElixirBlogWeb.CoreComponents

  attr :posts, :list, required: true
  attr :current_index, :integer, default: 0

  def carousel(assigns) do
    ~H"""
    <div class="relative bg-gray-900 overflow-hidden" id="carousel" data-carousel phx-hook="Carousel">
      <!-- Carousel Items -->
      <div class="relative h-96 md:h-[500px]">
        <%= for {post, index} <- Enum.with_index(@posts) do %>
          <div
            data-carousel-slide
            class={[
              "absolute inset-0 transition-opacity duration-500",
              if(index == @current_index, do: "opacity-100", else: "opacity-0 pointer-events-none")
            ]}
          >
            <div class="relative h-full">
              <!-- Background Image -->
              <div class="absolute inset-0 bg-gradient-to-r from-purple-600 to-blue-600"></div>
              
    <!-- Content -->
              <div class="relative h-full max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 flex items-center">
                <div class="max-w-3xl">
                  <h2 class="text-4xl md:text-5xl font-bold text-white mb-4">
                    {post.title}
                  </h2>
                  <p class="text-xl text-gray-200 mb-6">
                    {post.summary}
                  </p>
                  <div class="flex items-center gap-4 text-gray-300 mb-6">
                    <span>{post.author}</span>
                    <span>•</span>
                    <span>{post.reading_time}분 읽기</span>
                  </div>
                  <.link
                    navigate={"/posts/#{post.slug}"}
                    class="inline-block bg-white text-gray-900 px-8 py-3 rounded-lg font-semibold hover:bg-gray-100 transition-colors"
                  >
                    읽어보기 →
                  </.link>
                </div>
              </div>
            </div>
          </div>
        <% end %>
      </div>
      
    <!-- Navigation Buttons -->
      <%= if length(@posts) > 1 do %>
        <button
          phx-click="carousel_prev"
          class="absolute left-4 top-1/2 -translate-y-1/2 bg-white/20 hover:bg-white/30 text-white p-3 rounded-full transition-colors backdrop-blur-sm"
        >
          <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
          </svg>
        </button>

        <button
          phx-click="carousel_next"
          class="absolute right-4 top-1/2 -translate-y-1/2 bg-white/20 hover:bg-white/30 text-white p-3 rounded-full transition-colors backdrop-blur-sm"
        >
          <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
          </svg>
        </button>
        
    <!-- Indicators -->
        <div class="absolute bottom-6 left-0 right-0 flex justify-center gap-2">
          <%= for index <- 0..(length(@posts) - 1) do %>
            <button
              phx-click="carousel_goto"
              phx-value-index={index}
              class={[
                "w-2 h-2 rounded-full transition-all",
                if(index == @current_index,
                  do: "bg-white w-8",
                  else: "bg-white/50 hover:bg-white/75"
                )
              ]}
            />
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end
