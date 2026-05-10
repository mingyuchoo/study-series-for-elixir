defmodule WebWeb.UserLoginLive do
  use WebWeb, :live_view

  def render(assigns) do
    ~H"""
    <div class="min-h-[calc(100vh-4rem)] bg-base-100 px-6 py-16">
      <div class="mx-auto w-full max-w-md">
        <div class="mb-8 border-b border-base-300 pb-6">
          <h1 class="text-4xl font-light leading-tight">로그인</h1>
          <p class="mt-3 text-sm text-base-content/60">
            계정이 없나요? <.link navigate={~p"/users/register"} class="link link-primary">회원가입</.link>
          </p>
        </div>

        <div class="card w-full bg-base-100">
          <div class="card-body gap-4">
            <.form
              for={@form}
              id="login_form"
              action={~p"/users/log_in"}
              phx-update="ignore"
            >
              <.input
                field={@form[:email]}
                type="email"
                label="이메일"
                autocomplete="username"
                required
              />
              <.input
                field={@form[:password]}
                type="password"
                label="비밀번호"
                autocomplete="current-password"
                required
              />
              <.input
                field={@form[:remember_me]}
                type="checkbox"
                label="로그인 상태 유지"
              />
              <button
                type="submit"
                phx-disable-with="로그인 중..."
                class="btn btn-primary btn-block mt-2"
              >
                로그인
              </button>
            </.form>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    email = Phoenix.Flash.get(socket.assigns.flash, :email)
    form = to_form(%{"email" => email}, as: "user")
    {:ok, assign(socket, form: form), temporary_assigns: [form: form]}
  end
end
