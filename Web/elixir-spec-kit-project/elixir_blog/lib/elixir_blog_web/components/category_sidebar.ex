defmodule ElixirBlogWeb.Components.CategorySidebar do
  use Phoenix.Component
  import ElixirBlogWeb.CoreComponents

  @doc """
  Renders a category sidebar with all available categories/tags.

  ## Examples

      <.category_sidebar tags={@tags} current_tag_slug={@current_tag_slug} />
  """
  attr :tags, :list, required: true, doc: "List of Tag structs to display"
  attr :current_tag_slug, :string, default: nil, doc: "Slug of currently selected tag"

  def category_sidebar(assigns) do
    ~H"""
    <div data-category-sidebar class="bg-white rounded-lg shadow-md p-6 sticky top-4">
      <h3 class="text-xl font-bold text-gray-900 mb-4">카테고리</h3>

      <div class="space-y-2">
        <%= for tag <- @tags do %>
          <.link
            navigate={"/categories/#{tag.slug}"}
            class={[
              "block px-3 py-2 rounded-md transition-colors text-sm font-medium",
              if(@current_tag_slug == tag.slug,
                do: "bg-primary-100 text-primary-700",
                else: "text-gray-700 hover:bg-gray-100 hover:text-primary-600"
              )
            ]}
          >
            {tag.name}
          </.link>
        <% end %>
      </div>

      <%= if @current_tag_slug do %>
        <div class="mt-6 pt-6 border-t border-gray-200">
          <.link
            navigate="/"
            class="block w-full text-center px-4 py-2 bg-gray-100 hover:bg-gray-200 text-gray-700 rounded-md transition-colors text-sm font-medium"
          >
            모든 포스트 보기
          </.link>
        </div>
      <% end %>
    </div>
    """
  end
end
