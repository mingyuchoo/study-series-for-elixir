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
end
