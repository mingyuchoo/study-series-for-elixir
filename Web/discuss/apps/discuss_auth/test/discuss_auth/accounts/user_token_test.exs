defmodule DiscussAuth.Accounts.UserTokenTest do
  use Discuss.DataCase

  alias DiscussAuth.Accounts.UserToken

  import DiscussAuth.AccountsFixtures

  describe "build_session_token/1" do
    test "세션 토큰을 생성한다" do
      user = user_fixture()
      {token, user_token} = UserToken.build_session_token(user)
      assert is_binary(token)
      assert byte_size(token) == 32
      assert user_token.context == "session"
      assert user_token.user_id == user.id
    end
  end

  describe "build_email_token/2" do
    test "이메일 인증 토큰을 생성한다" do
      user = user_fixture()
      {encoded_token, user_token} = UserToken.build_email_token(user, "confirm")
      assert is_binary(encoded_token)
      assert user_token.context == "confirm"
      assert user_token.sent_to == user.email
      assert user_token.user_id == user.id
    end

    test "비밀번호 재설정 토큰을 생성한다" do
      user = user_fixture()
      {encoded_token, user_token} = UserToken.build_email_token(user, "reset_password")
      assert is_binary(encoded_token)
      assert user_token.context == "reset_password"
    end
  end

  describe "verify_session_token_query/1" do
    test "유효한 세션 토큰으로 쿼리를 반환한다" do
      user = user_fixture()
      {token, user_token} = UserToken.build_session_token(user)
      Discuss.Repo.insert!(user_token)

      assert {:ok, query} = UserToken.verify_session_token_query(token)
      assert Discuss.Repo.one(query).id == user.id
    end
  end

  describe "verify_email_token_query/2" do
    test "유효한 이메일 토큰으로 쿼리를 반환한다" do
      user = user_fixture()
      {encoded_token, user_token} = UserToken.build_email_token(user, "confirm")
      Discuss.Repo.insert!(user_token)

      assert {:ok, query} = UserToken.verify_email_token_query(encoded_token, "confirm")
      assert Discuss.Repo.one(query).id == user.id
    end

    test "유효하지 않은 base64 토큰으로 :error를 반환한다" do
      assert :error = UserToken.verify_email_token_query("!!!invalid!!!", "confirm")
    end
  end

  describe "by_token_and_context_query/2" do
    test "토큰과 컨텍스트로 쿼리를 생성한다" do
      user = user_fixture()
      {token, user_token} = UserToken.build_session_token(user)
      Discuss.Repo.insert!(user_token)

      query = UserToken.by_token_and_context_query(token, "session")
      assert Discuss.Repo.one(query)
    end
  end

  describe "by_user_and_contexts_query/2" do
    test ":all 컨텍스트로 사용자의 모든 토큰을 조회한다" do
      user = user_fixture()
      {_, user_token} = UserToken.build_session_token(user)
      Discuss.Repo.insert!(user_token)

      query = UserToken.by_user_and_contexts_query(user, :all)
      assert Discuss.Repo.one(query)
    end

    test "특정 컨텍스트 목록으로 토큰을 조회한다" do
      user = user_fixture()
      {_, user_token} = UserToken.build_email_token(user, "confirm")
      Discuss.Repo.insert!(user_token)

      query = UserToken.by_user_and_contexts_query(user, ["confirm"])
      assert Discuss.Repo.one(query)
    end
  end
end
