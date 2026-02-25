defmodule Playa.Accounts.Users do
  @moduledoc """
  사용자 관리 모듈

  사용자의 CRUD 작업과 이메일/닉네임 변경을 담당합니다.
  """

  import Ecto.Query, warn: false
  alias Playa.Repo
  alias Playa.Accounts.{User, Role, RoleUser}

  @doc """
  이메일로 사용자 조회
  """
  def get_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
    |> Repo.preload(:roles)
  end

  @doc """
  이메일과 비밀번호로 사용자 인증
  """
  def get_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  ID로 사용자 조회 (존재하지 않으면 예외 발생)
  """
  def get!(id) do
    Repo.get!(User, id)
    |> Repo.preload(:roles)
  end

  @doc """
  모든 사용자 목록 조회
  """
  def list do
    User
    |> select([u], u)
    |> order_by([u], asc: u.id)
    |> preload(:roles)
    |> Repo.all()
  end

  @doc """
  특정 역할을 가진 사용자 목록 조회
  """
  def list_by_role_id(role_id) do
    User
    |> select([u], u)
    |> join(:inner, [u], ru in RoleUser, on: ru.user_id == u.id)
    |> join(:inner, [u, ru], r in Role, on: ru.role_id == r.id and r.id == ^role_id)
    |> order_by([u], asc: u.id)
    |> Repo.all()
  end

  @doc """
  사용자 등록
  """
  def register(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, user} -> {:ok, Repo.preload(user, :roles)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  사용자 생성 (register의 별칭)
  """
  def create(attrs \\ %{}), do: register(attrs)

  @doc """
  사용자 정보 업데이트
  """
  def update(%User{} = user, attrs) do
    user
    |> User.registration_changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, user} -> {:ok, Repo.preload(user, :roles)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  사용자 닉네임 업데이트
  """
  def update_nickname(%User{} = user, attrs) do
    user
    |> User.nickname_changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, user} -> {:ok, Repo.preload(user, :roles)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  사용자 이메일 변경 (비밀번호 확인 포함)
  """
  def apply_email_change(user, password, attrs) do
    user
    |> User.email_changeset(attrs)
    |> User.validate_current_password(password)
    |> Ecto.Changeset.apply_action(:update)
  end

  @doc """
  사용자 삭제
  """
  def delete(%User{} = user) do
    Repo.delete(user)
  end

  @doc """
  사용자가 관리자인지 확인
  """
  def admin?(%User{} = user) do
    Enum.any?(user.roles, fn role -> role.name == "Admin" end)
  end

  @doc """
  사용자 등록 changeset 반환
  """
  def change_registration(%User{} = user, attrs \\ %{}) do
    user
    |> Repo.preload(:roles)
    |> User.registration_changeset(attrs, hash_password: false, validate_email: false)
  end

  @doc """
  사용자 이메일 변경 changeset 반환
  """
  def change_email(user, attrs \\ %{}) do
    User.email_changeset(user, attrs, validate_email: false)
  end

  @doc """
  사용자 닉네임 변경 changeset 반환
  """
  def change_nickname(user, attrs \\ %{}) do
    User.nickname_changeset(user, attrs)
  end

  @doc """
  사용자 changeset 반환 (범용)
  """
  def change(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs)
  end
end
