defmodule PlayaWeb.UserLive.Show do
  use PlayaWeb, :live_view

  alias Playa.Accounts

  @impl true
  def mount(%{"user_id" => user_id}, _session, socket) do
    role_user = Accounts.list_role_user_by_user_id(user_id) |> List.first()
    role_user_changeset = Accounts.change_role_user(role_user)

    {:ok,
     socket
     |> assign(:role_form, to_form(role_user_changeset))
     |> assign(:remain_roles, Accounts.list_remain_roles_by_user_id(user_id))
     |> stream(:my_roles, Accounts.list_roles_by_user_id(user_id))}
  end

  @impl true
  def handle_params(%{"user_id" => user_id}, _, socket) do
    {:noreply,
     socket
     |> assign(:page_title, page_title(socket.assigns.live_action))
     |> assign(:user, Accounts.get_user!(user_id))}
  end

  defp page_title(:show), do: "Show User"
  defp page_title(:edit), do: "Edit User"

  @impl true
  def handle_event("delete", %{"user_id" => user_id}, socket) do
    user = Accounts.get_user!(user_id)
    # NOTE:
    # User가 삭제될 때 Role에 user_count 1 차감
    Enum.map(user.roles, fn role -> Accounts.decrease_user_count(role) end)

    {:ok, _} = Accounts.delete_user(user)

    {:noreply, push_navigate(socket, to: "/accounts/users")}
  end

  @impl true
  def handle_event("validate_role", %{"role_user" => role_user_param}, socket) do
    changeset =
      %Accounts.RoleUser{}
      |> Accounts.RoleUser.changeset(role_user_param)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :role_form, to_form(changeset))}
  end

  @impl true
  def handle_event("save_role", %{"role_user" => role_user_param}, socket) do
    role_user_param
    |> Accounts.create_role_user()
    |> case do
      {:ok, role_user} ->
        {:noreply,
         socket
         |> assign(:remain_roles, Accounts.list_remain_roles_by_user_id(role_user.user_id))
         |> stream_insert(:my_roles, role_user.role_id |> Accounts.get_role!())}

      {:error, _change_set} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("delete_role", %{"role_id" => role_id, "user_id" => user_id}, socket) do
    role_user = Accounts.get_role_user(role_id, user_id)
    role = Accounts.get_role!(role_id)
    {:ok, _} = role_user |> Accounts.delete_role_user()

    {:noreply,
     socket
     |> assign(
       :remain_roles,
       role_user.user_id
       |> Accounts.list_remain_roles_by_user_id()
     )
     |> stream_delete(:my_roles, role)}
  end
end
