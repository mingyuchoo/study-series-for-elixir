defmodule DiscussAuth.Seeder do
  @moduledoc """
  앱 시작 시 초기 데이터를 생성하는 모듈.
  모든 함수는 멱등성을 보장하므로 여러 번 실행해도 안전합니다.
  """

  alias Discuss.Repo
  alias DiscussAuth.Accounts.User, as: AuthUser
  alias Discuss.Admin

  @admin_email "admin@email.com"
  @admin_password "password!"

  @doc """
  초기 시드 데이터를 생성한다.
  """
  def run do
    seed_admin_user()
  end

  defp seed_admin_user do
    auth_user = upsert_auth_user()
    if auth_user, do: ensure_admin_profile(auth_user)
  end

  # accounts_users 레코드를 생성하거나 기존 레코드를 반환한다.
  defp upsert_auth_user do
    changeset =
      %AuthUser{}
      |> AuthUser.registration_changeset(
        %{email: @admin_email, password: @admin_password},
        validate_email: false
      )
      |> Ecto.Changeset.put_change(:confirmed_at, DateTime.utc_now() |> DateTime.truncate(:second))

    case Repo.insert(changeset, on_conflict: :nothing, conflict_target: [:email]) do
      {:ok, %AuthUser{id: nil}} ->
        # 이미 존재함 — 기존 레코드 반환
        Repo.get_by(AuthUser, email: @admin_email)

      {:ok, auth_user} ->
        auth_user

      {:error, changeset} ->
        IO.warn("[Seeder] auth_user 생성 실패: #{inspect(changeset.errors)}")
        nil
    end
  end

  # users 테이블에 admin 프로필이 없으면 생성한다.
  defp ensure_admin_profile(auth_user) do
    unless Repo.get_by(Admin.User, auth_user_id: auth_user.id) do
      case Admin.create_user(%{
             name: "관리자",
             email: @admin_email,
             role: "admin",
             address: "-",
             auth_user_id: auth_user.id
           }) do
        {:ok, _admin} ->
          IO.puts("[Seeder] 관리자 계정 생성 완료: #{@admin_email}")

        {:error, changeset} ->
          IO.warn("[Seeder] admin 프로필 생성 실패: #{inspect(changeset.errors)}")
      end
    end
  end
end
