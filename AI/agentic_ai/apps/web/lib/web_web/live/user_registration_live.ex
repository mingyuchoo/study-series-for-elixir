defmodule WebWeb.UserRegistrationLive do
  use WebWeb, :live_view

  alias Core.Contexts.Accounts
  alias Core.Schema.User

  def render(assigns) do
    ~H"""
    <div class="hero min-h-[calc(100vh-4rem)]">
      <div class="hero-content flex-col w-full max-w-md">
        <div class="text-center">
          <h1 class="text-3xl font-bold">계정 만들기</h1>
          <p class="py-2 text-base-content/60">
            이미 계정이 있나요?
            <.link navigate={~p"/users/log_in"} class="link link-primary">로그인</.link>
          </p>
        </div>

        <div class="card bg-base-100 shadow-xl w-full">
          <div class="card-body gap-4">
            <.form
              for={@form}
              id="registration_form"
              phx-submit="save"
              phx-change="validate"
              phx-trigger-action={@trigger_submit}
              action={~p"/users/log_in?_action=registered"}
              method="post"
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
                label="비밀번호 (최소 8자)"
                autocomplete="new-password"
                required
              />
              <button type="submit" phx-disable-with="생성 중..." class="btn btn-primary btn-block mt-2">
                계정 만들기
              </button>
            </.form>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    changeset = Accounts.change_user_registration(%User{})

    socket =
      socket
      |> assign(trigger_submit: false, check_errors: false)
      |> assign_form(changeset)

    {:ok, socket, temporary_assigns: [form: nil]}
  end

  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        {:ok, _} =
          Core.Schema.User.confirm_changeset(user)
          |> Core.Repo.update()

        changeset = Accounts.change_user_registration(user)
        {:noreply, socket |> assign(trigger_submit: true) |> assign_form(changeset)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, socket |> assign(check_errors: true) |> assign_form(changeset)}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_registration(%User{}, user_params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")

    if changeset.valid? do
      assign(socket, form: form, check_errors: false)
    else
      assign(socket, form: form)
    end
  end
end
