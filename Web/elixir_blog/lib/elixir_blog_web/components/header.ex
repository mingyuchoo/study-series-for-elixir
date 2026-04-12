defmodule ElixirBlogWeb.Components.Header do
  use Phoenix.Component
  import ElixirBlogWeb.CoreComponents

  attr :current_path, :string, default: "/"

  def header(assigns) do
    ~H"""
    <header class="bg-white shadow-sm sticky top-0 z-50">
      <nav class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="flex justify-between h-16 items-center">
          <div class="flex items-center">
            <.link navigate="/" class="text-2xl font-bold text-primary-600 hover:text-primary-700">
              Elixir 블로그
            </.link>
          </div>

          <div class="flex space-x-8">
            <.link
              navigate="/"
              class={[
                "text-base font-medium transition-colors",
                if(@current_path == "/",
                  do: "text-primary-600",
                  else: "text-gray-700 hover:text-primary-600"
                )
              ]}
            >
              홈
            </.link>
            <.link
              navigate="/categories"
              class={[
                "text-base font-medium transition-colors",
                if(String.starts_with?(@current_path, "/categories"),
                  do: "text-primary-600",
                  else: "text-gray-700 hover:text-primary-600"
                )
              ]}
            >
              카테고리
            </.link>
          </div>
        </div>
      </nav>
    </header>
    """
  end
end
