defmodule WebWeb.UserLoginLive do
  use WebWeb, :live_view

  def render(assigns) do
    ~H"""
    <div class="min-h-screen hero bg-base-200">
      <div class="hero-content flex-col w-full max-w-md">
        <div class="text-center">
          <h1 class="text-3xl font-bold">로그인</h1>
          <p class="py-2 text-base-content/60">
            계정이 없나요?
            <.link navigate={~p"/users/register"} class="link link-primary">회원가입</.link>
          </p>
        </div>

        <div class="card bg-base-100 shadow-xl w-full">
          <div class="card-body">
            <.form
              for={@form}
              id="login_form"
              action={~p"/users/log_in"}
              phx-update="ignore"
              class="space-y-4"
            >
              <div class="form-control">
                <label class="label" for={@form[:email].id}>
                  <span class="label-text">이메일</span>
                </label>
                <input
                  type="email"
                  name={@form[:email].name}
                  id={@form[:email].id}
                  value={Phoenix.HTML.Form.normalize_value("email", @form[:email].value)}
                  required
                  autocomplete="username"
                  class="input input-bordered w-full"
                />
              </div>

              <div class="form-control">
                <label class="label" for={@form[:password].id}>
                  <span class="label-text">비밀번호</span>
                </label>
                <input
                  type="password"
                  name={@form[:password].name}
                  id={@form[:password].id}
                  required
                  autocomplete="current-password"
                  class="input input-bordered w-full"
                />
              </div>

              <div class="form-control">
                <label class="label cursor-pointer justify-start gap-2">
                  <input
                    type="checkbox"
                    name={@form[:remember_me].name}
                    class="checkbox checkbox-sm"
                  />
                  <span class="label-text">로그인 상태 유지</span>
                </label>
              </div>

              <button type="submit" phx-disable-with="로그인 중..." class="btn btn-primary btn-block">
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
