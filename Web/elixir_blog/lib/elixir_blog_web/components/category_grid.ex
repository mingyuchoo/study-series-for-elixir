defmodule ElixirBlogWeb.Components.CategoryGrid do
  use Phoenix.Component

  attr :categories, :list, required: true
  attr :title, :string, default: nil
  attr :columns, :integer, default: 3

  def category_grid(assigns) do
    ~H"""
    <div class="py-12" data-testid="category-grid" role="region" aria-label="카테고리 목록">
      <%= if @title do %>
        <h2 class="text-3xl font-bold text-gray-900 mb-8">{@title}</h2>
      <% end %>

      <div class={[
        "grid gap-6",
        case @columns do
          1 -> "grid-cols-1"
          2 -> "grid-cols-1 md:grid-cols-2"
          3 -> "grid-cols-1 md:grid-cols-2 lg:grid-cols-3"
          4 -> "grid-cols-1 md:grid-cols-2 lg:grid-cols-4"
          _ -> "grid-cols-1 md:grid-cols-2 lg:grid-cols-3"
        end
      ]}>
        <%= for category <- @categories do %>
          <.link
            navigate={"/categories/#{category.slug}"}
            class="group"
            data-testid="category-card"
            aria-label={"#{category.name} 카테고리 보기, #{category.post_count}개의 포스트"}
          >
            <div
              class="bg-white rounded-lg shadow-md p-6 hover:shadow-xl transition-all duration-200 border border-gray-100"
              role="article"
            >
              <!-- Category Header -->
              <div class="flex items-start justify-between mb-4">
                <div class="flex-1">
                  <h3 class="text-xl font-bold text-gray-900 group-hover:text-purple-600 transition-colors mb-2">
                    {category.name}
                  </h3>
                  <p class="text-sm text-gray-500">
                    {category.slug}
                  </p>
                </div>
                <!-- Arrow Icon -->
                <div
                  class="text-gray-400 group-hover:text-purple-600 group-hover:translate-x-1 transition-all"
                  aria-hidden="true"
                >
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    class="h-5 w-5"
                    viewBox="0 0 20 20"
                    fill="currentColor"
                  >
                    <path
                      fill-rule="evenodd"
                      d="M7.293 14.707a1 1 0 010-1.414L10.586 10 7.293 6.707a1 1 0 011.414-1.414l4 4a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0z"
                      clip-rule="evenodd"
                    />
                  </svg>
                </div>
              </div>
              <!-- Post Count -->
              <div class="mt-4 pt-4 border-t border-gray-100">
                <div class="flex items-center gap-2">
                  <!-- Document Icon -->
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    class="h-5 w-5 text-gray-400"
                    viewBox="0 0 20 20"
                    fill="currentColor"
                    aria-hidden="true"
                  >
                    <path d="M9 2a2 2 0 00-2 2v8a2 2 0 002 2h6a2 2 0 002-2V6.414A2 2 0 0016.414 5L14 2.586A2 2 0 0012.586 2H9z" />
                    <path d="M3 8a2 2 0 012-2v10h8a2 2 0 01-2 2H5a2 2 0 01-2-2V8z" />
                  </svg>
                  <span class="text-lg font-semibold text-gray-700" aria-label={"{category.post_count}개의 포스트"}>
                    {category.post_count}개의 포스트
                  </span>
                </div>
              </div>
            </div>
          </.link>
        <% end %>
      </div>
    </div>
    """
  end
end
