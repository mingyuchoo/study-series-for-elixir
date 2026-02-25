defmodule Playa.Accounts.RoleAssignments do
  @moduledoc """
  역할-사용자 관계 관리 모듈

  사용자와 역할 간의 M:N 관계를 관리합니다.
  """

  import Ecto.Query, warn: false
  alias Playa.Repo
  alias Playa.Accounts.{Role, RoleUser}

  @doc """
  모든 역할-사용자 관계 목록 조회
  """
  def list do
    RoleUser
    |> select([ru], ru)
    |> order_by([ru], asc: ru.id)
    |> Repo.all()
  end

  @doc """
  특정 사용자의 역할 할당 목록 조회
  """
  def list_by_user_id(user_id) do
    RoleUser
    |> select([ru], ru)
    |> where([ru], ru.user_id == ^user_id)
    |> order_by([ru], asc: ru.id)
    |> Repo.all()
  end

  @doc """
  특정 사용자가 할당받지 않은 역할 목록 조회
  """
  def list_unassigned_roles(user_id) do
    Role
    |> select([r], r)
    |> join(:left, [r], ru in RoleUser, on: r.id == ru.role_id and ru.user_id == ^user_id)
    |> where([r, ru], is_nil(ru.role_id))
    |> order_by([r], asc: r.id)
    |> Repo.all()
  end

  @doc """
  역할과 사용자로 할당 관계 조회 (존재하지 않으면 예외 발생)
  """
  def get!(role_id, user_id) do
    RoleUser
    |> select([ru], ru)
    |> where([ru], ru.role_id == ^role_id and ru.user_id == ^user_id)
    |> Repo.one!()
  end

  @doc """
  역할과 사용자로 할당 관계 조회
  """
  def get(role_id, user_id) do
    RoleUser
    |> select([ru], ru)
    |> where([ru], ru.role_id == ^role_id and ru.user_id == ^user_id)
    |> Repo.one()
  end

  @doc """
  역할-사용자 관계 생성
  """
  def create(attrs \\ %{}) do
    %RoleUser{}
    |> RoleUser.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  역할-사용자 관계 업데이트
  """
  def update(%RoleUser{} = role_user, attrs) do
    role_user
    |> RoleUser.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  역할-사용자 관계 삭제
  """
  def delete(%RoleUser{} = role_user) do
    Repo.delete(role_user)
  end

  @doc """
  역할-사용자 changeset 반환
  """
  def change(%RoleUser{} = role_user, attrs \\ %{}) do
    RoleUser.changeset(role_user, attrs)
  end
end
