defmodule PlayaWeb.UserLive.FormComponent do
  use PlayaWeb, :live_component

  alias Playa.Accounts
  alias Playa.Accounts.User

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>Use this form to manage user records in your database.</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="user-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:email]} type="text" label="Email" placeholder="Your email" />
        <.input field={@form[:password]} type="password" label="Password" placeholder="Your password" />
        <.input field={@form[:nickname]} type="text" label="Nickname" placeholder="Your nickname" />
        <!--
        리스트 셀렉트박스 추가
          - prompt 를 넣으면 기본 선택 안 됨
        -->
        <.input
          field={@form[:role_id]}
          type="select"
          label="Roles"
          options={Enum.map(@roles, &{&1.name, &1.id})}
        />
        <:actions>
          <.button phx-disable-with="Saving..."><.icon name="hero-check" />Save</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{user: user} = assigns, socket) do
    changeset = Accounts.change_user(user)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_registration(%User{}, user_params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    save_user(socket, socket.assigns.action, user_params)
  end

  defp save_user(socket, :edit, user_params) do
    case Accounts.update_user(socket.assigns.user, user_params) do
      {:ok, user} ->
        notify_parent({:saved, user})

        {:noreply,
         socket
         |> put_flash(:info, "User updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_user(socket, :new, user_params) do
    case Accounts.create_user(user_params) do
      {:ok, user} ->
        user_params["role_id"]
        |> Accounts.get_role!()

        notify_parent({:saved, user})

        # NOTE:
        # User가 추가될 때 Role에 user_count 1 가산
        Enum.map(user.roles, fn role ->
          Accounts.increase_user_count(role)
        end)

        {:ok, _} =
          Accounts.deliver_user_confirmation_instructions(
            user,
            &url(~p"/users/confirm/#{&1}")
          )

        {:noreply,
         socket
         |> assign(trigger_submit: true)
         |> put_flash(:info, "User created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, socket |> assign(check_errors: true) |> assign_form(changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    # NOTE:
    # 폼을 만들 때 :roles 데이터 가져오기
    socket
    |> assign(:form, to_form(changeset))
    |> assign(:roles, Accounts.list_roles())
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
