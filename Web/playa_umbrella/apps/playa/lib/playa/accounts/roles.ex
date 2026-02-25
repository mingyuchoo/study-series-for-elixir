defmodule Playa.Accounts.Roles do
  @moduledoc """
  역할 관리 모듈

  역할의 CRUD 작업과 사용자 카운트 관리를 담당합니다.
  """

  import Ecto.Query, warn: false
  alias Playa.Repo
  alias Playa.Accounts.{Role, User, RoleUser}

  @doc """
  모든 역할 목록 조회
  """
  def list do
    Role
    |> select([r], r)
    |> order_by([r], asc: r.id)
    |> preload(:users)
    |> Repo.all()
  end

  @doc """
  특정 사용자의 역할 목록 조회
  """
  def list_by_user_id(user_id) do
    Role
    |> select([r], r)
    |> join(:inner, [r], ru in RoleUser, on: ru.role_id == r.id)
    |> join(:inner, [r, ru], u in User, on: ru.user_id == u.id and u.id == ^user_id)
    |> order_by([r], asc: r.id)
    |> preload([:users])
    |> Repo.all()
  end

  @doc """
  특정 사용자가 가지지 않은 역할 목록 조회
  """
  def list_remaining_by_user_id(user_id) do
    from(r in Role,
      as: :role,
      where:
        not exists(
          from(ru in RoleUser,
            where: ru.user_id == ^user_id and ru.role_id == parent_as(:role).id
          )
        ),
      preload: [:users]
    )
    |> Repo.all()
  end

  @doc """
  ID로 역할 조회 (존재하지 않으면 예외 발생)
  """
  def get!(id) do
    Role
    |> select([r], r)
    |> where([r], r.id == ^id)
    |> preload(:users)
    |> Repo.one!()
  end

  @doc """
  이름으로 기본 역할 조회
  """
  def get_default(role_name) do
    Role
    |> select([r], r)
    |> where([r], r.name == ^role_name)
    |> preload(:users)
    |> Repo.one!()
  end

  @doc """
  역할 생성
  """
  def create(attrs \\ %{}) do
    %Role{}
    |> Role.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, role} -> {:ok, Repo.preload(role, :users)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  역할 정보 업데이트
  """
  def update(%Role{} = role, attrs) do
    role
    |> Repo.preload(:users)
    |> Role.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  역할 삭제
  """
  def delete(%Role{} = role) do
    role
    |> Repo.preload(:users)
    |> Repo.delete()
  end

  @doc """
  역할 changeset 반환
  """
  def change(%Role{} = role, attrs \\ %{}) do
    role
    |> Repo.preload(:users)
    |> Role.changeset(attrs)
  end

  @doc """
  역할의 사용자 카운트 증가
  """
  def increase_user_count(%Role{} = role) do
    role
    |> Repo.preload(:users)
    |> Role.changeset(%{user_count: role.user_count + 1})
    |> Repo.update()
  end

  @doc """
  역할의 사용자 카운트 감소
  """
  def decrease_user_count(%Role{} = role) do
    new_user_count = max(role.user_count - 1, 0)

    role
    |> Repo.preload(:users)
    |> Role.changeset(%{user_count: new_user_count})
    |> Repo.update()
  end
end
