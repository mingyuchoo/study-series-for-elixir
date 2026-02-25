defmodule Playa.Accounts.SessionsTest do
  use Playa.DataCase

  alias Playa.Accounts.{Sessions, User, UserToken}
  alias Playa.Repo

  import Playa.AccountsFixtures

  describe "generate_token/1" do
    test "세션 토큰을 생성하고 저장한다" do
      user = user_fixture()
      token = Sessions.generate_token(user)

      assert is_binary(token)
      assert byte_size(token) == 32

      # 토큰이 데이터베이스에 저장되었는지 확인
      assert Repo.get_by(UserToken, user_id: user.id, context: "session")
    end

    test "동일 사용자에 대해 여러 세션 토큰을 생성할 수 있다" do
      user = user_fixture()
      token1 = Sessions.generate_token(user)
      token2 = Sessions.generate_token(user)

      assert token1 != token2

      tokens =
        Repo.all(from t in UserToken, where: t.user_id == ^user.id and t.context == "session")

      assert length(tokens) == 2
    end
  end

  describe "get_user_by_token/1" do
    test "유효한 세션 토큰으로 사용자를 조회한다" do
      user = user_fixture()
      token = Sessions.generate_token(user)

      fetched_user = Sessions.get_user_by_token(token)
      assert fetched_user.id == user.id
      assert fetched_user.email == user.email
    end

    test "잘못된 토큰으로는 사용자를 조회할 수 없다" do
      invalid_token = :crypto.strong_rand_bytes(32)
      assert Sessions.get_user_by_token(invalid_token) == nil
    end

    test "만료된 토큰으로는 사용자를 조회할 수 없다" do
      user = user_fixture()
      token = Sessions.generate_token(user)

      # 토큰을 61일 전으로 백데이트
      Repo.update_all(
        from(t in UserToken, where: t.user_id == ^user.id and t.context == "session"),
        set: [inserted_at: ~N[2020-01-01 00:00:00]]
      )

      assert Sessions.get_user_by_token(token) == nil
    end
  end

  describe "delete_token/1" do
    test "세션 토큰을 삭제한다" do
      user = user_fixture()
      token = Sessions.generate_token(user)

      assert Repo.get_by(UserToken, user_id: user.id, context: "session")
      assert Sessions.delete_token(token) == :ok
      refute Repo.get_by(UserToken, user_id: user.id, context: "session")
    end

    test "존재하지 않는 토큰 삭제는 에러를 발생시키지 않는다" do
      invalid_token = :crypto.strong_rand_bytes(32)
      assert Sessions.delete_token(invalid_token) == :ok
    end

    test "다른 사용자의 세션 토큰은 삭제하지 않는다" do
      user1 = user_fixture()
      user2 = user_fixture()
      token1 = Sessions.generate_token(user1)
      token2 = Sessions.generate_token(user2)

      Sessions.delete_token(token1)
      fetched_user = Sessions.get_user_by_token(token2)
      assert fetched_user
      assert fetched_user.id == user2.id
    end
  end

  describe "deliver_confirmation_instructions/2" do
    test "이메일 확인 토큰을 생성하고 이메일을 전송한다" do
      user = user_fixture()

      result =
        Sessions.deliver_confirmation_instructions(user, &"http://example.com/confirm/#{&1}")

      assert {:ok, _} = result
      assert Repo.get_by(UserToken, user_id: user.id, context: "confirm")
    end

    test "이미 확인된 사용자에게는 확인 이메일을 보내지 않는다" do
      user = user_fixture()
      confirmed_user = Repo.update!(User.confirm_changeset(user))

      result =
        Sessions.deliver_confirmation_instructions(
          confirmed_user,
          &"http://example.com/confirm/#{&1}"
        )

      assert {:error, :already_confirmed} = result
    end
  end

  describe "confirm_user/1" do
    test "유효한 토큰으로 사용자를 확인한다" do
      user = user_fixture()

      {token, _user_token} = UserToken.build_email_token(user, "confirm")

      Repo.insert!(%UserToken{
        token: :crypto.hash(:sha256, Base.url_decode64!(token, padding: false)),
        context: "confirm",
        sent_to: user.email,
        user_id: user.id
      })

      assert {:ok, confirmed_user} = Sessions.confirm_user(token)
      assert confirmed_user.confirmed_at
      refute is_nil(confirmed_user.confirmed_at)

      # 토큰이 삭제되었는지 확인
      refute Repo.get_by(UserToken, user_id: user.id, context: "confirm")
    end

    test "잘못된 토큰으로는 사용자를 확인할 수 없다" do
      assert Sessions.confirm_user("invalid_token") == :error
    end

    test "이미 사용된 토큰으로는 사용자를 확인할 수 없다" do
      user = user_fixture()

      {token, user_token} = UserToken.build_email_token(user, "confirm")
      Repo.insert!(user_token)

      assert {:ok, _} = Sessions.confirm_user(token)
      assert Sessions.confirm_user(token) == :error
    end

    test "만료된 확인 토큰으로는 사용자를 확인할 수 없다" do
      user = user_fixture()

      {token, user_token} = UserToken.build_email_token(user, "confirm")
      Repo.insert!(user_token)

      # 토큰을 8일 전으로 백데이트 (유효기간 7일)
      Repo.update_all(
        from(t in UserToken, where: t.user_id == ^user.id and t.context == "confirm"),
        set: [inserted_at: ~N[2020-01-01 00:00:00]]
      )

      assert Sessions.confirm_user(token) == :error
    end
  end

  describe "deliver_update_email_instructions/3" do
    test "이메일 업데이트 토큰을 생성하고 이메일을 전송한다" do
      user = user_fixture()
      current_email = user.email

      result =
        Sessions.deliver_update_email_instructions(
          user,
          current_email,
          &"http://example.com/update-email/#{&1}"
        )

      assert {:ok, _} = result

      token = Repo.get_by(UserToken, user_id: user.id, context: "change:#{current_email}")
      assert token
      assert token.sent_to == current_email
    end
  end

  describe "update_user_email/2" do
    test "유효한 토큰으로 사용자 이메일을 업데이트한다" do
      user = user_fixture()
      new_email = "new-#{user.email}"

      {token, user_token} = UserToken.build_email_token(user, "change:#{user.email}")

      # sent_to를 새 이메일로 설정
      user_token = %{user_token | sent_to: new_email}
      Repo.insert!(user_token)

      assert :ok = Sessions.update_user_email(user, token)

      updated_user = Repo.get!(User, user.id)
      assert updated_user.email == new_email
      assert updated_user.confirmed_at

      # 토큰이 삭제되었는지 확인
      refute Repo.get_by(UserToken, user_id: user.id)
    end

    test "잘못된 토큰으로는 이메일을 업데이트할 수 없다" do
      user = user_fixture()
      assert Sessions.update_user_email(user, "invalid_token") == :error
    end

    test "만료된 토큰으로는 이메일을 업데이트할 수 없다" do
      user = user_fixture()
      new_email = "new-#{user.email}"

      {token, user_token} = UserToken.build_email_token(user, "change:#{user.email}")
      user_token = %{user_token | sent_to: new_email}
      Repo.insert!(user_token)

      # 토큰을 8일 전으로 백데이트 (유효기간 7일)
      Repo.update_all(
        from(t in UserToken, where: t.user_id == ^user.id),
        set: [inserted_at: ~N[2020-01-01 00:00:00]]
      )

      assert Sessions.update_user_email(user, token) == :error
    end
  end

  describe "deliver_reset_password_instructions/2" do
    test "비밀번호 재설정 토큰을 생성하고 이메일을 전송한다" do
      user = user_fixture()

      result =
        Sessions.deliver_reset_password_instructions(
          user,
          &"http://example.com/reset-password/#{&1}"
        )

      assert {:ok, _} = result
      assert Repo.get_by(UserToken, user_id: user.id, context: "reset_password")
    end
  end

  describe "get_user_by_reset_password_token/1" do
    test "유효한 비밀번호 재설정 토큰으로 사용자를 조회한다" do
      user = user_fixture()

      {token, user_token} = UserToken.build_email_token(user, "reset_password")
      Repo.insert!(user_token)

      fetched_user = Sessions.get_user_by_reset_password_token(token)
      assert fetched_user.id == user.id
    end

    test "잘못된 토큰으로는 사용자를 조회할 수 없다" do
      assert Sessions.get_user_by_reset_password_token("invalid_token") == nil
    end

    test "만료된 토큰으로는 사용자를 조회할 수 없다" do
      user = user_fixture()

      {token, user_token} = UserToken.build_email_token(user, "reset_password")
      Repo.insert!(user_token)

      # 토큰을 2일 전으로 백데이트 (유효기간 1일)
      Repo.update_all(
        from(t in UserToken, where: t.user_id == ^user.id and t.context == "reset_password"),
        set: [inserted_at: ~N[2020-01-01 00:00:00]]
      )

      assert Sessions.get_user_by_reset_password_token(token) == nil
    end
  end

  describe "reset_user_password/2" do
    test "유효한 속성으로 비밀번호를 재설정한다" do
      user = user_fixture()

      {:ok, updated_user} = Sessions.reset_user_password(user, %{password: "new valid password"})

      assert updated_user.id == user.id
      assert User.valid_password?(updated_user, "new valid password")

      # 모든 토큰이 삭제되었는지 확인
      assert Repo.all(from t in UserToken, where: t.user_id == ^user.id) == []
    end

    test "유효하지 않은 속성으로는 비밀번호를 재설정할 수 없다" do
      user = user_fixture()

      {:error, changeset} = Sessions.reset_user_password(user, %{password: "short"})

      assert "should be at least 12 character(s)" in errors_on(changeset).password
    end

    test "비밀번호 재설정 시 모든 토큰이 삭제된다" do
      user = user_fixture()

      # 여러 토큰 생성
      Sessions.generate_token(user)
      {_token, user_token} = UserToken.build_email_token(user, "confirm")
      Repo.insert!(user_token)

      assert length(Repo.all(from t in UserToken, where: t.user_id == ^user.id)) == 2

      {:ok, _} = Sessions.reset_user_password(user, %{password: "new valid password"})

      assert Repo.all(from t in UserToken, where: t.user_id == ^user.id) == []
    end
  end

  describe "change_password/2" do
    test "비밀번호 변경 changeset을 반환한다" do
      user = user_fixture()
      changeset = Sessions.change_password(user)

      assert %Ecto.Changeset{} = changeset
      assert changeset.data.id == user.id
    end

    test "속성이 있는 changeset을 반환한다" do
      user = user_fixture()
      changeset = Sessions.change_password(user, %{password: "new password"})

      assert changeset.changes.password == "new password"
      # hash_password: false이므로 해시되지 않음
      refute Map.has_key?(changeset.changes, :hashed_password)
    end
  end

  describe "update_user_password/3" do
    test "현재 비밀번호가 맞으면 비밀번호를 업데이트한다" do
      user = user_fixture()
      current_password = valid_user_password()

      {:ok, updated_user} =
        Sessions.update_user_password(
          user,
          current_password,
          %{password: "new valid password"}
        )

      assert User.valid_password?(updated_user, "new valid password")
      refute User.valid_password?(updated_user, current_password)
    end

    test "현재 비밀번호가 틀리면 비밀번호를 업데이트하지 않는다" do
      user = user_fixture()

      {:error, changeset} =
        Sessions.update_user_password(
          user,
          "invalid password",
          %{password: "new valid password"}
        )

      assert "is not valid" in errors_on(changeset).current_password
      assert User.valid_password?(user, valid_user_password())
    end

    test "유효하지 않은 새 비밀번호로는 업데이트하지 않는다" do
      user = user_fixture()
      current_password = valid_user_password()

      {:error, changeset} =
        Sessions.update_user_password(
          user,
          current_password,
          %{password: "short"}
        )

      assert "should be at least 12 character(s)" in errors_on(changeset).password
    end

    test "비밀번호 업데이트 시 모든 토큰이 삭제된다" do
      user = user_fixture()
      current_password = valid_user_password()

      # 토큰 생성
      Sessions.generate_token(user)
      {_token, user_token} = UserToken.build_email_token(user, "confirm")
      Repo.insert!(user_token)

      assert length(Repo.all(from t in UserToken, where: t.user_id == ^user.id)) == 2

      {:ok, _} =
        Sessions.update_user_password(
          user,
          current_password,
          %{password: "new valid password"}
        )

      assert Repo.all(from t in UserToken, where: t.user_id == ^user.id) == []
    end
  end
end
