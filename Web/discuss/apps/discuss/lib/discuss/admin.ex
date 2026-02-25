defmodule Discuss.Admin do
  @moduledoc """
  사용자 관리 관련 비즈니스 로직을 캡슐화하는 Context 모듈.
  """

  import Ecto.Query, warn: false
  alias Discuss.Repo
  alias Discuss.Admin.User

  def list_users do
    Repo.all(User)
  end

  def get_user!(id) do
    Repo.get!(User, id)
  end

  def create_user(attrs \\ %{}) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  def update_user(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  def delete_user(%User{} = user) do
    Repo.delete(user)
  end

  def change_user(%User{} = user, attrs \\ %{}) do
    User.changeset(user, attrs)
  end
end
