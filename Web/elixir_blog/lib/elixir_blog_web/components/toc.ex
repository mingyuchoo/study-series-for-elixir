defmodule ElixirBlogWeb.Components.Toc do
  use Phoenix.Component

  attr :headings, :list, required: true

  def toc(assigns) do
    ~H"""
    <div class="bg-white rounded-lg shadow-md p-6 sticky top-24">
      <h3 class="text-lg font-bold text-gray-900 mb-4">목차</h3>
      <nav class="space-y-2" id="toc-nav" phx-hook="SmoothScroll">
        <%= for heading <- @headings do %>
          <a
            href={"##{heading.id}"}
            class={[
              "block text-sm hover:text-primary transition-colors",
              if(heading.level == 2, do: "font-medium text-gray-900", else: "pl-4 text-gray-600")
            ]}
          >
            {heading.text}
          </a>
        <% end %>
      </nav>
    </div>
    """
  end
end
