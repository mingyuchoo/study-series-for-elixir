defmodule DiscussAuth.AccountsTest do
  use Discuss.DataCase

  alias DiscussAuth.Accounts

  import DiscussAuth.AccountsFixtures

  describe "register_user/1" do
    test "유효한 데이터로 사용자를 등록한다" do
      attrs = valid_user_attributes()
      assert {:ok, user} = Accounts.register_user(attrs)
      assert user.email == attrs.email
      assert is_binary(user.hashed_password)
      assert is_nil(user.confirmed_at)
      assert is_nil(user.password)
    end

    test "이메일이 없으면 에러를 반환한다" do
      assert {:error, changeset} = Accounts.register_user(%{password: valid_user_password()})
      assert %{email: ["can't be blank"]} = errors_on(changeset)
    end

    test "비밀번호가 8자 미만이면 에러를 반환한다" do
      attrs = valid_user_attributes(%{password: "short"})
      assert {:error, changeset} = Accounts.register_user(attrs)
      assert %{password: [_msg]} = errors_on(changeset)
    end

    test "중복 이메일은 에러를 반환한다" do
      %{email: email} = user_fixture()
      assert {:error, changeset} = Accounts.register_user(%{email: email, password: valid_user_password()})
      assert "has already been taken" in errors_on(changeset).email
    end
  end

  describe "get_user_by_email/1" do
    test "존재하는 이메일로 사용자를 반환한다" do
      user = user_fixture()
      assert found = Accounts.get_user_by_email(user.email)
      assert found.id == user.id
    end

    test "존재하지 않는 이메일로 nil을 반환한다" do
      refute Accounts.get_user_by_email("unknown@example.com")
    end
  end

  describe "get_user_by_email_and_password/2" do
    test "유효한 자격 증명으로 사용자를 반환한다" do
      %{id: id, email: email} = user_fixture()

      assert %{id: ^id} =
               Accounts.get_user_by_email_and_password(email, valid_user_password())
    end

    test "잘못된 비밀번호로 nil을 반환한다" do
      %{email: email} = user_fixture()
      refute Accounts.get_user_by_email_and_password(email, "wrong_password")
    end

    test "잘못된 이메일로 nil을 반환한다" do
      refute Accounts.get_user_by_email_and_password("unknown@example.com", "hello_world!")
    end
  end

  describe "get_user!/1" do
    test "존재하는 사용자를 반환한다" do
      user = user_fixture()
      assert Accounts.get_user!(user.id).id == user.id
    end

    test "존재하지 않는 ID로 에러를 발생시킨다" do
      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_user!(0)
      end
    end
  end

  describe "change_user_registration/2" do
    test "사용자 등록 changeset을 반환한다" do
      changeset = Accounts.change_user_registration(%DiscussAuth.Accounts.User{})
      assert %Ecto.Changeset{} = changeset
    end
  end

  describe "change_user_email/2" do
    test "이메일 변경 changeset을 반환한다" do
      user = user_fixture()
      changeset = Accounts.change_user_email(user)
      assert %Ecto.Changeset{} = changeset
    end
  end

  describe "change_user_password/2" do
    test "비밀번호 변경 changeset을 반환한다" do
      user = user_fixture()
      changeset = Accounts.change_user_password(user)
      assert %Ecto.Changeset{} = changeset
    end
  end

  describe "update_user_password/3" do
    test "올바른 비밀번호로 비밀번호를 변경한다" do
      user = user_fixture()

      assert {:ok, _updated} =
               Accounts.update_user_password(user, valid_user_password(), %{
                 password: "new_valid_password!",
                 password_confirmation: "new_valid_password!"
               })

      assert Accounts.get_user_by_email_and_password(user.email, "new_valid_password!")
    end

    test "틀린 비밀번호로 에러를 반환한다" do
      user = user_fixture()

      assert {:error, changeset} =
               Accounts.update_user_password(user, "wrong_password", %{
                 password: "new_valid_password!",
                 password_confirmation: "new_valid_password!"
               })

      assert %{current_password: [_]} = errors_on(changeset)
    end
  end

  describe "generate_user_session_token/1" do
    test "세션 토큰을 생성한다" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      assert is_binary(token)
      assert byte_size(token) == 32
    end
  end

  describe "get_user_by_session_token/1" do
    setup do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      %{user: user, token: token}
    end

    test "유효한 토큰으로 사용자를 반환한다", %{user: user, token: token} do
      assert session_user = Accounts.get_user_by_session_token(token)
      assert session_user.id == user.id
    end

    test "잘못된 토큰으로는 nil을 반환한다" do
      refute Accounts.get_user_by_session_token(:crypto.strong_rand_bytes(32))
    end
  end

  describe "delete_user_session_token/1" do
    test "세션 토큰을 삭제한다" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      assert Accounts.get_user_by_session_token(token)

      Accounts.delete_user_session_token(token)
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "deliver_user_confirmation_instructions/2" do
    test "미인증 사용자에게 인증 이메일을 발송한다" do
      user = user_fixture()

      assert {:ok, encoded_token} =
               Accounts.deliver_user_confirmation_instructions(user, &"http://example.com/confirm/#{&1}")

      assert is_binary(encoded_token)
    end

    test "이미 인증된 사용자에게는 에러를 반환한다" do
      user = user_fixture()

      # 직접 confirmed_at 설정
      user
      |> Ecto.Changeset.change(confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second))
      |> Discuss.Repo.update!()

      updated_user = Accounts.get_user!(user.id)

      assert {:error, :already_confirmed} =
               Accounts.deliver_user_confirmation_instructions(updated_user, &"http://example.com/confirm/#{&1}")
    end
  end

  describe "confirm_user/1" do
    test "유효한 토큰으로 사용자를 인증한다" do
      user = user_fixture()

      {:ok, encoded_token} =
        Accounts.deliver_user_confirmation_instructions(user, &"http://example.com/confirm/#{&1}")

      assert {:ok, confirmed_user} = Accounts.confirm_user(encoded_token)
      assert confirmed_user.confirmed_at
    end

    test "유효하지 않은 토큰으로 :error를 반환한다" do
      assert :error = Accounts.confirm_user("invalid_token")
    end
  end

  describe "deliver_user_reset_password_instructions/2" do
    test "비밀번호 재설정 이메일을 발송한다" do
      user = user_fixture()

      assert {:ok, encoded_token} =
               Accounts.deliver_user_reset_password_instructions(user, &"http://example.com/reset/#{&1}")

      assert is_binary(encoded_token)
    end
  end

  describe "get_user_by_reset_password_token/1" do
    test "유효한 토큰으로 사용자를 반환한다" do
      user = user_fixture()

      {:ok, encoded_token} =
        Accounts.deliver_user_reset_password_instructions(user, &"http://example.com/reset/#{&1}")

      assert found = Accounts.get_user_by_reset_password_token(encoded_token)
      assert found.id == user.id
    end

    test "유효하지 않은 토큰으로 nil을 반환한다" do
      refute Accounts.get_user_by_reset_password_token("invalid_token")
    end
  end

  describe "reset_user_password/2" do
    test "유효한 데이터로 비밀번호를 재설정한다" do
      user = user_fixture()

      assert {:ok, _updated} =
               Accounts.reset_user_password(user, %{
                 password: "new_password!",
                 password_confirmation: "new_password!"
               })

      assert Accounts.get_user_by_email_and_password(user.email, "new_password!")
    end

    test "유효하지 않은 데이터로 에러를 반환한다" do
      user = user_fixture()

      assert {:error, changeset} =
               Accounts.reset_user_password(user, %{password: "short"})

      assert %{password: [_]} = errors_on(changeset)
    end
  end
end
