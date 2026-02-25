defmodule Playa.Accounts.UserTokenTest do
  use Playa.DataCase

  alias Playa.Accounts.{User, UserToken}
  alias Playa.Repo

  import Playa.AccountsFixtures

  describe "build_session_token/1" do
    test "세션 토큰과 토큰 구조체를 생성한다" do
      user = user_fixture()
      {token, user_token} = UserToken.build_session_token(user)

      assert is_binary(token)
      assert byte_size(token) == 32

      assert %UserToken{} = user_token
      assert user_token.token == token
      assert user_token.context == "session"
      assert user_token.user_id == user.id
    end

    test "동일 사용자에 대해 다른 토큰을 생성한다" do
      user = user_fixture()
      {token1, _} = UserToken.build_session_token(user)
      {token2, _} = UserToken.build_session_token(user)

      assert token1 != token2
    end
  end

  describe "verify_session_token_query/1" do
    test "유효한 세션 토큰 쿼리를 반환한다" do
      user = user_fixture()
      {token, user_token} = UserToken.build_session_token(user)
      Repo.insert!(user_token)

      assert {:ok, query} = UserToken.verify_session_token_query(token)
      assert user = Repo.one(query)
      assert user.id == user.id
    end

    test "만료된 세션 토큰은 조회되지 않는다" do
      user = user_fixture()
      {token, user_token} = UserToken.build_session_token(user)
      Repo.insert!(user_token)

      # 토큰을 61일 전으로 백데이트 (세션 유효기간 60일)
      Repo.update_all(
        from(t in UserToken, where: t.user_id == ^user.id),
        set: [inserted_at: ~N[2020-01-01 00:00:00]]
      )

      {:ok, query} = UserToken.verify_session_token_query(token)
      assert Repo.one(query) == nil
    end
  end

  describe "build_email_token/2" do
    test "confirm 컨텍스트로 이메일 토큰을 생성한다" do
      user = user_fixture()
      {encoded_token, user_token} = UserToken.build_email_token(user, "confirm")

      assert is_binary(encoded_token)

      assert String.contains?(encoded_token, "_") or String.contains?(encoded_token, "-") or
               byte_size(encoded_token) > 40

      assert %UserToken{} = user_token
      assert user_token.context == "confirm"
      assert user_token.sent_to == user.email
      assert user_token.user_id == user.id

      # 토큰은 해시되어 있어야 함
      assert byte_size(user_token.token) == 32
      assert user_token.token != encoded_token
    end

    test "reset_password 컨텍스트로 이메일 토큰을 생성한다" do
      user = user_fixture()
      {encoded_token, user_token} = UserToken.build_email_token(user, "reset_password")

      assert is_binary(encoded_token)
      assert user_token.context == "reset_password"
      assert user_token.sent_to == user.email
    end

    test "change 컨텍스트로 이메일 토큰을 생성한다" do
      user = user_fixture()
      context = "change:#{user.email}"
      {encoded_token, user_token} = UserToken.build_email_token(user, context)

      assert is_binary(encoded_token)
      assert user_token.context == context
      assert user_token.sent_to == user.email
    end

    test "매번 다른 토큰을 생성한다" do
      user = user_fixture()
      {token1, _} = UserToken.build_email_token(user, "confirm")
      {token2, _} = UserToken.build_email_token(user, "confirm")

      assert token1 != token2
    end
  end

  describe "verify_email_token_query/2" do
    test "유효한 confirm 토큰 쿼리를 반환한다" do
      user = user_fixture()
      {encoded_token, user_token} = UserToken.build_email_token(user, "confirm")
      Repo.insert!(user_token)

      assert {:ok, query} = UserToken.verify_email_token_query(encoded_token, "confirm")
      assert fetched_user = Repo.one(query)
      assert fetched_user.id == user.id
    end

    test "유효한 reset_password 토큰 쿼리를 반환한다" do
      user = user_fixture()
      {encoded_token, user_token} = UserToken.build_email_token(user, "reset_password")
      Repo.insert!(user_token)

      assert {:ok, query} = UserToken.verify_email_token_query(encoded_token, "reset_password")
      assert fetched_user = Repo.one(query)
      assert fetched_user.id == user.id
    end

    test "잘못된 토큰은 에러를 반환한다" do
      assert UserToken.verify_email_token_query("invalid_token", "confirm") == :error
    end

    test "잘못된 컨텍스트는 사용자를 조회하지 않는다" do
      user = user_fixture()
      {encoded_token, user_token} = UserToken.build_email_token(user, "confirm")
      Repo.insert!(user_token)

      {:ok, query} = UserToken.verify_email_token_query(encoded_token, "reset_password")
      assert Repo.one(query) == nil
    end

    test "만료된 confirm 토큰은 조회되지 않는다" do
      user = user_fixture()
      {encoded_token, user_token} = UserToken.build_email_token(user, "confirm")
      Repo.insert!(user_token)

      # 토큰을 8일 전으로 백데이트 (confirm 유효기간 7일)
      Repo.update_all(
        from(t in UserToken, where: t.user_id == ^user.id),
        set: [inserted_at: ~N[2020-01-01 00:00:00]]
      )

      {:ok, query} = UserToken.verify_email_token_query(encoded_token, "confirm")
      assert Repo.one(query) == nil
    end

    test "만료된 reset_password 토큰은 조회되지 않는다" do
      user = user_fixture()
      {encoded_token, user_token} = UserToken.build_email_token(user, "reset_password")
      Repo.insert!(user_token)

      # 토큰을 2일 전으로 백데이트 (reset_password 유효기간 1일)
      Repo.update_all(
        from(t in UserToken, where: t.user_id == ^user.id),
        set: [inserted_at: ~N[2020-01-01 00:00:00]]
      )

      {:ok, query} = UserToken.verify_email_token_query(encoded_token, "reset_password")
      assert Repo.one(query) == nil
    end

    test "이메일이 변경된 경우 토큰은 무효화된다" do
      user = user_fixture()
      {encoded_token, user_token} = UserToken.build_email_token(user, "confirm")
      Repo.insert!(user_token)

      # 사용자 이메일 변경
      Repo.update!(User.email_changeset(user, %{email: "new-#{user.email}"}))

      {:ok, query} = UserToken.verify_email_token_query(encoded_token, "confirm")
      assert Repo.one(query) == nil
    end
  end

  describe "verify_change_email_token_query/2" do
    test "유효한 이메일 변경 토큰 쿼리를 반환한다" do
      user = user_fixture()
      context = "change:#{user.email}"
      {encoded_token, user_token} = UserToken.build_email_token(user, context)
      Repo.insert!(user_token)

      assert {:ok, query} = UserToken.verify_change_email_token_query(encoded_token, context)
      assert token_from_db = Repo.one(query)
      assert token_from_db.user_id == user.id
    end

    test "잘못된 토큰은 에러를 반환한다" do
      assert UserToken.verify_change_email_token_query("invalid_token", "change:test@example.com") ==
               :error
    end

    test "change: 접두사가 없는 컨텍스트는 실패한다" do
      user = user_fixture()
      {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{user.email}")
      Repo.insert!(user_token)

      # change: 접두사가 없는 컨텍스트로 검증 시도
      assert_raise FunctionClauseError, fn ->
        UserToken.verify_change_email_token_query(encoded_token, "invalid_context")
      end
    end

    test "만료된 이메일 변경 토큰은 조회되지 않는다" do
      user = user_fixture()
      context = "change:#{user.email}"
      {encoded_token, user_token} = UserToken.build_email_token(user, context)
      Repo.insert!(user_token)

      # 토큰을 8일 전으로 백데이트 (change_email 유효기간 7일)
      Repo.update_all(
        from(t in UserToken, where: t.user_id == ^user.id),
        set: [inserted_at: ~N[2020-01-01 00:00:00]]
      )

      {:ok, query} = UserToken.verify_change_email_token_query(encoded_token, context)
      assert Repo.one(query) == nil
    end

    test "잘못된 컨텍스트는 토큰을 조회하지 않는다" do
      user = user_fixture()
      context = "change:#{user.email}"
      {encoded_token, user_token} = UserToken.build_email_token(user, context)
      Repo.insert!(user_token)

      wrong_context = "change:other@example.com"
      {:ok, query} = UserToken.verify_change_email_token_query(encoded_token, wrong_context)
      assert Repo.one(query) == nil
    end
  end

  describe "by_token_and_context_query/2" do
    test "토큰과 컨텍스트로 쿼리를 생성한다" do
      user = user_fixture()
      {token, user_token} = UserToken.build_session_token(user)
      Repo.insert!(user_token)

      query = UserToken.by_token_and_context_query(token, "session")
      assert fetched_token = Repo.one(query)
      assert fetched_token.token == token
      assert fetched_token.context == "session"
    end

    test "일치하지 않는 토큰은 조회되지 않는다" do
      user = user_fixture()
      {_token, user_token} = UserToken.build_session_token(user)
      Repo.insert!(user_token)

      wrong_token = :crypto.strong_rand_bytes(32)
      query = UserToken.by_token_and_context_query(wrong_token, "session")
      assert Repo.one(query) == nil
    end

    test "일치하지 않는 컨텍스트는 조회되지 않는다" do
      user = user_fixture()
      {token, user_token} = UserToken.build_session_token(user)
      Repo.insert!(user_token)

      query = UserToken.by_token_and_context_query(token, "confirm")
      assert Repo.one(query) == nil
    end
  end

  describe "by_user_and_contexts_query/2" do
    setup do
      user = user_fixture()

      # 여러 종류의 토큰 생성
      {_token1, session_token} = UserToken.build_session_token(user)
      Repo.insert!(session_token)

      {_token2, confirm_token} = UserToken.build_email_token(user, "confirm")
      Repo.insert!(confirm_token)

      {_token3, reset_token} = UserToken.build_email_token(user, "reset_password")
      Repo.insert!(reset_token)

      %{user: user}
    end

    test "모든 토큰을 조회한다 (:all)", %{user: user} do
      query = UserToken.by_user_and_contexts_query(user, :all)
      tokens = Repo.all(query)

      assert length(tokens) == 3
      contexts = Enum.map(tokens, & &1.context)
      assert "session" in contexts
      assert "confirm" in contexts
      assert "reset_password" in contexts
    end

    test "특정 컨텍스트의 토큰만 조회한다", %{user: user} do
      query = UserToken.by_user_and_contexts_query(user, ["confirm", "reset_password"])
      tokens = Repo.all(query)

      assert length(tokens) == 2
      contexts = Enum.map(tokens, & &1.context)
      assert "confirm" in contexts
      assert "reset_password" in contexts
      refute "session" in contexts
    end

    test "단일 컨텍스트 리스트로 조회한다", %{user: user} do
      query = UserToken.by_user_and_contexts_query(user, ["session"])
      tokens = Repo.all(query)

      assert length(tokens) == 1
      assert hd(tokens).context == "session"
    end

    test "존재하지 않는 컨텍스트는 빈 결과를 반환한다", %{user: user} do
      query = UserToken.by_user_and_contexts_query(user, ["nonexistent"])
      assert Repo.all(query) == []
    end

    test "다른 사용자의 토큰은 조회되지 않는다", %{user: user1} do
      user2 = user_fixture()
      {_token, user2_token} = UserToken.build_session_token(user2)
      Repo.insert!(user2_token)

      query = UserToken.by_user_and_contexts_query(user1, :all)
      tokens = Repo.all(query)

      # user1은 3개, user2의 토큰은 포함되지 않음
      assert length(tokens) == 3
      assert Enum.all?(tokens, fn t -> t.user_id == user1.id end)
    end
  end

  describe "토큰 보안" do
    test "세션 토큰은 해시되지 않고 저장된다" do
      user = user_fixture()
      {token, user_token} = UserToken.build_session_token(user)

      # 세션 토큰은 원본 그대로 저장
      assert user_token.token == token
    end

    test "이메일 토큰은 해시되어 저장된다" do
      user = user_fixture()
      {encoded_token, user_token} = UserToken.build_email_token(user, "confirm")

      # 이메일 토큰은 해시되어 저장
      assert user_token.token != encoded_token
      assert byte_size(user_token.token) == 32

      # encoded_token은 Base64 URL 인코딩되어 있음
      assert is_binary(encoded_token)
    end

    test "동일 컨텍스트라도 매번 다른 해시가 생성된다" do
      user = user_fixture()
      {_token1, user_token1} = UserToken.build_email_token(user, "confirm")
      {_token2, user_token2} = UserToken.build_email_token(user, "confirm")

      assert user_token1.token != user_token2.token
    end
  end

  describe "토큰 유효기간" do
    test "세션 토큰은 60일 유효하다" do
      user = user_fixture()
      {token, user_token} = UserToken.build_session_token(user)
      Repo.insert!(user_token)

      # 59일 전
      Repo.update_all(
        from(t in UserToken, where: t.user_id == ^user.id),
        set: [
          inserted_at: DateTime.add(DateTime.utc_now(), -59, :day) |> DateTime.truncate(:second)
        ]
      )

      {:ok, query} = UserToken.verify_session_token_query(token)
      assert Repo.one(query)
    end

    test "confirm 토큰은 7일 유효하다" do
      user = user_fixture()
      {token, user_token} = UserToken.build_email_token(user, "confirm")
      Repo.insert!(user_token)

      # 6일 전
      Repo.update_all(
        from(t in UserToken, where: t.user_id == ^user.id),
        set: [
          inserted_at: DateTime.add(DateTime.utc_now(), -6, :day) |> DateTime.truncate(:second)
        ]
      )

      {:ok, query} = UserToken.verify_email_token_query(token, "confirm")
      assert Repo.one(query)
    end

    test "reset_password 토큰은 1일 유효하다" do
      user = user_fixture()
      {token, user_token} = UserToken.build_email_token(user, "reset_password")
      Repo.insert!(user_token)

      # 23시간 전
      Repo.update_all(
        from(t in UserToken, where: t.user_id == ^user.id),
        set: [
          inserted_at: DateTime.add(DateTime.utc_now(), -23, :hour) |> DateTime.truncate(:second)
        ]
      )

      {:ok, query} = UserToken.verify_email_token_query(token, "reset_password")
      assert Repo.one(query)
    end
  end
end
