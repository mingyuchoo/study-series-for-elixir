defmodule DiscussAuth.SeederTest do
  use Discuss.DataCase

  alias Discuss.Repo
  alias DiscussAuth.Accounts
  alias DiscussAuth.Accounts.User, as: AuthUser
  alias Discuss.Admin

  @admin_email "admin@email.com"
  @admin_password "password!"

  describe "DiscussAuth.Seeder.run/0" do
    test "auth_user가 올바른 이메일로 생성된다" do
      DiscussAuth.Seeder.run()

      auth_user = Repo.get_by(AuthUser, email: @admin_email)
      assert auth_user != nil
      assert auth_user.email == @admin_email
    end

    test "auth_user의 비밀번호가 해싱되어 저장된다" do
      DiscussAuth.Seeder.run()

      auth_user = Repo.get_by(AuthUser, email: @admin_email)
      assert is_binary(auth_user.hashed_password)
      refute auth_user.hashed_password == @admin_password
    end

    test "auth_user가 이메일 인증 완료 상태로 생성된다" do
      DiscussAuth.Seeder.run()

      auth_user = Repo.get_by(AuthUser, email: @admin_email)
      assert auth_user.confirmed_at != nil
    end

    test "admin 프로필이 role=admin으로 생성된다" do
      DiscussAuth.Seeder.run()

      auth_user = Repo.get_by(AuthUser, email: @admin_email)
      admin = Admin.get_user_by_auth_user_id(auth_user.id)

      assert admin != nil
      assert admin.role == "admin"
      assert admin.email == @admin_email
      assert admin.auth_user_id == auth_user.id
    end

    test "관리자 계정으로 로그인이 된다" do
      DiscussAuth.Seeder.run()

      assert %AuthUser{} = Accounts.get_user_by_email_and_password(@admin_email, @admin_password)
    end

    test "시드를 두 번 실행해도 중복 생성되지 않는다" do
      DiscussAuth.Seeder.run()
      DiscussAuth.Seeder.run()

      count =
        Repo.aggregate(
          from(u in AuthUser, where: u.email == ^@admin_email),
          :count
        )

      assert count == 1
    end

    test "이미 관리자 프로필이 있으면 다시 생성하지 않는다" do
      DiscussAuth.Seeder.run()
      auth_user = Repo.get_by(AuthUser, email: @admin_email)
      admin_before = Admin.get_user_by_auth_user_id(auth_user.id)

      # 두 번째 실행
      DiscussAuth.Seeder.run()
      admin_after = Admin.get_user_by_auth_user_id(auth_user.id)

      assert admin_before.id == admin_after.id
    end
  end
end
