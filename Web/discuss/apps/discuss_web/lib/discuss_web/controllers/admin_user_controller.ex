defmodule DiscussWeb.AdminUserController do
  use DiscussWeb, :controller
  alias Discuss.Admin

  def index(conn, _params) do
    users = Admin.list_users()
    render(conn, :index, layout: false, users: users)
  end

  def new(conn, _params) do
    changeset = Admin.change_user(%Admin.User{})
    render(conn, :new, layout: false, changeset: changeset)
  end

  def create(conn, %{"user" => user_params}) do
    case Admin.create_user(user_params) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "\"#{user.name}\" 사용자가 생성되었습니다.")
        |> redirect(to: ~p"/admin/users")

      {:error, changeset} ->
        render(conn, :new, layout: false, changeset: changeset)
    end
  end

  def show(conn, %{"id" => id}) do
    user = Admin.get_user!(id)
    render(conn, :show, layout: false, user: user)
  end

  def edit(conn, %{"id" => id}) do
    user = Admin.get_user!(id)
    changeset = Admin.change_user(user)
    render(conn, :edit, layout: false, changeset: changeset, user: user)
  end

  def update(conn, %{"id" => id, "user" => user_params}) do
    user = Admin.get_user!(id)

    case Admin.update_user(user, user_params) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "\"#{user.name}\" 사용자가 업데이트되었습니다.")
        |> redirect(to: ~p"/admin/users")

      {:error, changeset} ->
        render(conn, :edit, layout: false, changeset: changeset, user: user)
    end
  end

  def delete(conn, %{"id" => id}) do
    user = Admin.get_user!(id)
    {:ok, _user} = Admin.delete_user(user)

    conn
    |> put_flash(:info, "사용자가 삭제되었습니다.")
    |> redirect(to: ~p"/admin/users")
  end
end
