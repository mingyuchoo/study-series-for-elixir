defmodule WebWeb.UserSettingsLive do
  use WebWeb, :live_view

  alias Core.Contexts.Accounts

  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto p-6 space-y-6">
      <div>
        <h1 class="text-3xl font-bold">계정 설정</h1>
        <p class="text-base-content/60">이메일 주소와 비밀번호를 관리합니다.</p>
      </div>

      <div class="card bg-base-100 shadow-xl">
        <div class="card-body gap-3">
          <h2 class="card-title">이메일 변경</h2>
          <.form
            for={@email_form}
            id="email_form"
            phx-submit="update_email"
            phx-change="validate_email"
          >
            <.input
              field={@email_form[:email]}
              type="email"
              label="새 이메일"
              autocomplete="username"
              required
            />
            <.input
              field={@email_form[:current_password]}
              type="password"
              label="현재 비밀번호"
              value={@email_form_current_password}
              autocomplete="current-password"
              required
            />
            <button type="submit" phx-disable-with="변경 중..." class="btn btn-primary mt-2">
              이메일 변경
            </button>
          </.form>
        </div>
      </div>

      <div class="card bg-base-100 shadow-xl">
        <div class="card-body gap-3">
          <h2 class="card-title">비밀번호 변경</h2>
          <.form
            for={@password_form}
            id="password_form"
            action={~p"/users/log_in?_action=password_updated"}
            method="post"
            phx-change="validate_password"
            phx-submit="update_password"
            phx-trigger-action={@trigger_submit}
          >
            <input
              name={@password_form[:email].name}
              type="hidden"
              id="hidden_email"
              value={@current_email}
            />
            <.input
              field={@password_form[:password]}
              type="password"
              label="새 비밀번호"
              autocomplete="new-password"
              required
            />
            <.input
              field={@password_form[:password_confirmation]}
              type="password"
              label="새 비밀번호 확인"
              autocomplete="new-password"
              required
            />
            <.input
              field={@password_form[:current_password]}
              type="password"
              label="현재 비밀번호"
              value={@current_password}
              autocomplete="current-password"
              required
            />
            <button type="submit" phx-disable-with="변경 중..." class="btn btn-primary mt-2">
              비밀번호 변경
            </button>
          </.form>
        </div>
      </div>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    email_changeset = Accounts.change_user_email(user)
    password_changeset = Accounts.change_user_password(user)

    socket =
      socket
      |> assign(:current_password, nil)
      |> assign(:email_form_current_password, nil)
      |> assign(:current_email, user.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:trigger_submit, false)

    {:ok, socket}
  end

  def handle_event("validate_email", params, socket) do
    %{"current_password" => password, "user" => user_params} = params

    email_form =
      socket.assigns.current_user
      |> Accounts.change_user_email(user_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form, email_form_current_password: password)}
  end

  def handle_event("update_email", params, socket) do
    %{"current_password" => password, "user" => user_params} = params
    user = socket.assigns.current_user

    case Accounts.apply_user_email(user, password, user_params) do
      {:ok, applied_user} ->
        {:ok, _} = Core.Repo.update(Ecto.Changeset.change(applied_user))

        socket =
          socket
          |> put_flash(:info, "이메일이 변경되었습니다.")
          |> assign(:current_email, applied_user.email)
          |> assign(:email_form, to_form(Accounts.change_user_email(applied_user)))
          |> assign(:current_user, applied_user)

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :email_form, to_form(Map.put(changeset, :action, :insert)))}
    end
  end

  def handle_event("validate_password", params, socket) do
    %{"current_password" => password, "user" => user_params} = params

    password_form =
      socket.assigns.current_user
      |> Accounts.change_user_password(user_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form, current_password: password)}
  end

  def handle_event("update_password", params, socket) do
    %{"current_password" => password, "user" => user_params} = params
    user = socket.assigns.current_user

    case Accounts.update_user_password(user, password, user_params) do
      {:ok, user} ->
        password_form =
          user
          |> Accounts.change_user_password(user_params)
          |> to_form()

        {:noreply, assign(socket, trigger_submit: true, password_form: password_form)}

      {:error, changeset} ->
        {:noreply, assign(socket, password_form: to_form(changeset))}
    end
  end
end
