defmodule ElixirBlogWeb.Components.SubscriptionForm do
  use Phoenix.Component
  import ElixirBlogWeb.CoreComponents

  attr :changeset, Ecto.Changeset, required: true
  attr :status, :atom, default: nil

  def subscription_form(assigns) do
    ~H"""
    <div class="bg-gradient-to-r from-purple-600 to-blue-600 py-16">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="max-w-3xl mx-auto text-center">
          <h2 class="text-3xl font-bold text-white mb-4">
            최신 글을 이메일로 받아보세요
          </h2>
          <p class="text-xl text-gray-100 mb-8">
            새로운 기술 블로그 포스트가 올라올 때마다 알림을 받으세요.
          </p>

          <.form
            :let={f}
            for={to_form(@changeset)}
            phx-submit="subscribe"
            phx-change="validate_subscription"
            class="flex flex-col sm:flex-row gap-4 justify-center"
          >
            <div class="flex-1 max-w-md">
              <.input
                field={f[:email]}
                type="email"
                placeholder="이메일 주소를 입력하세요"
                class="w-full px-4 py-3 rounded-lg border-0 focus:ring-2 focus:ring-white"
                required
              />
            </div>

            <.button
              type="submit"
              class="bg-white text-purple-600 px-8 py-3 rounded-lg font-semibold hover:bg-gray-100 transition-colors"
            >
              구독하기
            </.button>
          </.form>
          
    <!-- Status Messages -->
          <%= if @status == :success do %>
            <div class="mt-4 bg-white/20 backdrop-blur-sm text-white px-6 py-3 rounded-lg">
              ✓ 구독이 완료되었습니다! 감사합니다.
            </div>
          <% end %>

          <%= if @status == :duplicate do %>
            <div class="mt-4 bg-white/20 backdrop-blur-sm text-white px-6 py-3 rounded-lg">
              이미 구독하신 이메일입니다.
            </div>
          <% end %>

          <%= if @status == :error do %>
            <div class="mt-4 bg-red-500/80 backdrop-blur-sm text-white px-6 py-3 rounded-lg">
              오류가 발생했습니다. 다시 시도해주세요.
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
