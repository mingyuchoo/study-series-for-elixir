defmodule ElixirBlogWeb.Components.Footer do
  use Phoenix.Component

  def footer(assigns) do
    ~H"""
    <footer class="bg-gray-800 text-white mt-16">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
        <div class="grid grid-cols-1 md:grid-cols-3 gap-8">
          <div>
            <h3 class="text-lg font-semibold mb-4">Elixir 블로그</h3>
            <p class="text-gray-300">
              Elixir와 Phoenix에 대한 Elixir 기술 블로그입니다.
            </p>
          </div>

          <div>
            <h3 class="text-lg font-semibold mb-4">링크</h3>
            <ul class="space-y-2">
              <li>
                <a href="/" class="text-gray-300 hover:text-white transition-colors">
                  홈
                </a>
              </li>
              <li>
                <a href="/categories" class="text-gray-300 hover:text-white transition-colors">
                  카테고리
                </a>
              </li>
            </ul>
          </div>

          <div>
            <h3 class="text-lg font-semibold mb-4">정보</h3>
            <p class="text-gray-300 text-sm">
              © {DateTime.utc_now().year} Elixir 블로그. All rights reserved.
            </p>
            <p class="text-gray-300 text-sm mt-2">
              Built with Phoenix LiveView
            </p>
          </div>
        </div>
      </div>
    </footer>
    """
  end
end
