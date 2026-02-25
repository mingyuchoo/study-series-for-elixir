defmodule Auth.GuardianPipelineMaybeTest do
  use Auth.DataCase
  import Plug.Test
  import Plug.Conn

  alias Auth.GuardianPipelineMaybe
  alias Auth.Guardian
  alias Playa.Accounts

  setup do
    # 테스트용 사용자 생성
    {:ok, user} =
      Accounts.register_user(%{
        email: "test#{System.unique_integer()}@example.com",
        password: "hello world!"
      })

    # 유효한 토큰 생성
    {:ok, token, _claims} = Guardian.encode_and_sign(user)

    %{user: user, token: token}
  end

  describe "Guardian.Plug.Pipeline behaviour" do
    test "Guardian.Plug.Pipeline을 사용한다" do
      # 모듈이 Guardian.Plug.Pipeline을 사용하는지 확인
      assert function_exported?(GuardianPipelineMaybe, :init, 1)
      assert function_exported?(GuardianPipelineMaybe, :call, 2)
    end

    test "올바른 옵션으로 구성되어 있다" do
      # 파이프라인 초기화 옵션 확인
      opts = GuardianPipelineMaybe.init([])

      assert opts[:module] == Auth.Guardian
      assert opts[:error_handler] == Auth.GuardianErrorHandler
    end
  end

  describe "세션에서 토큰 검증 (VerifySession)" do
    test "세션에 유효한 토큰이 있으면 리소스를 로드한다", %{token: token, user: user} do
      conn =
        conn(:get, "/")
        |> init_test_session(%{guardian_default_token: token})
        |> GuardianPipelineMaybe.call([])

      # 리소스가 올바르게 로드되었는지 확인
      current_user = Guardian.Plug.current_resource(conn)
      assert current_user != nil
      assert current_user.id == user.id
    end

    test "세션에 토큰이 없어도 에러가 발생하지 않는다 (allow_blank: true)" do
      conn =
        conn(:get, "/")
        |> init_test_session(%{})
        |> GuardianPipelineMaybe.call([])

      # allow_blank: true이므로 토큰이 없어도 에러 없이 진행
      assert conn.status == nil or conn.status == 200
      assert Guardian.Plug.current_resource(conn) == nil
    end

    test "세션의 잘못된 토큰은 리소스를 로드하지 못한다" do
      # 형식은 맞지만 서명이 잘못된 토큰
      invalid_token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.invalid_signature"

      conn =
        conn(:get, "/")
        |> init_test_session(%{guardian_default_token: invalid_token})
        |> GuardianPipelineMaybe.call([])

      # allow_blank: true이므로 잘못된 토큰도 에러 없이 진행하지만 리소스는 로드되지 않음
      assert Guardian.Plug.current_resource(conn) == nil
    end
  end

  describe "헤더에서 토큰 검증 (VerifyHeader)" do
    test "Authorization 헤더에 유효한 Bearer 토큰이 있으면 리소스를 로드한다", %{
      token: token,
      user: user
    } do
      conn =
        conn(:get, "/")
        |> put_req_header("authorization", "Bearer #{token}")
        |> GuardianPipelineMaybe.call([])

      # 리소스가 올바르게 로드되었는지 확인
      current_user = Guardian.Plug.current_resource(conn)
      assert current_user != nil
      assert current_user.id == user.id
    end

    test "Authorization 헤더가 없어도 에러가 발생하지 않는다 (allow_blank: true)" do
      conn =
        conn(:get, "/")
        |> GuardianPipelineMaybe.call([])

      # allow_blank: true이므로 헤더가 없어도 에러 없이 진행
      assert conn.status == nil or conn.status == 200
      assert Guardian.Plug.current_resource(conn) == nil
    end

    test "잘못된 Bearer 토큰은 리소스를 로드하지 못한다" do
      # 형식은 맞지만 서명이 잘못된 토큰
      invalid_token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.invalid_signature"

      conn =
        conn(:get, "/")
        |> put_req_header("authorization", "Bearer #{invalid_token}")
        |> GuardianPipelineMaybe.call([])

      # allow_blank: true이므로 잘못된 토큰도 에러 없이 진행하지만 리소스는 로드되지 않음
      assert Guardian.Plug.current_resource(conn) == nil
    end

    test "Bearer가 아닌 다른 스킴은 무시된다" do
      conn =
        conn(:get, "/")
        |> put_req_header("authorization", "Basic sometoken")
        |> GuardianPipelineMaybe.call([])

      # Bearer 스킴이 아니므로 토큰이 검증되지 않음
      assert Guardian.Plug.current_resource(conn) == nil
    end
  end

  describe "리소스 로딩 (LoadResource)" do
    test "토큰이 검증되면 자동으로 리소스를 로드한다", %{token: token, user: user} do
      conn =
        conn(:get, "/")
        |> put_req_header("authorization", "Bearer #{token}")
        |> GuardianPipelineMaybe.call([])

      # Guardian.Plug.LoadResource가 자동으로 사용자를 로드함
      current_user = Guardian.Plug.current_resource(conn)
      assert current_user != nil
      assert current_user.id == user.id
      assert current_user.email == user.email
    end

    test "리소스를 로드할 수 없어도 allow_blank 덕분에 에러가 발생하지 않는다" do
      # 존재하지 않는 사용자 ID로 토큰 생성
      fake_claims = %{"sub" => "-1", "aud" => "auth"}
      {:ok, fake_token, _} = Guardian.encode_and_sign(%{id: -1}, fake_claims)

      conn =
        conn(:get, "/")
        |> put_req_header("authorization", "Bearer #{fake_token}")
        |> GuardianPipelineMaybe.call([])

      # allow_blank: true이므로 리소스 로드 실패해도 에러 없이 진행
      assert Guardian.Plug.current_resource(conn) == nil
    end
  end

  describe "파이프라인 통합" do
    test "세션과 헤더가 모두 있으면 세션이 먼저 확인된다", %{user: user} do
      # 세션용 토큰과 헤더용 토큰을 각각 생성
      {:ok, session_token, _} = Guardian.encode_and_sign(user)

      # 다른 사용자 생성
      {:ok, other_user} =
        Accounts.register_user(%{
          email: "other#{System.unique_integer()}@example.com",
          password: "hello world!"
        })

      {:ok, header_token, _} = Guardian.encode_and_sign(other_user)

      conn =
        conn(:get, "/")
        |> init_test_session(%{guardian_default_token: session_token})
        |> put_req_header("authorization", "Bearer #{header_token}")
        |> GuardianPipelineMaybe.call([])

      # VerifySession이 먼저 실행되므로 세션의 토큰이 사용됨
      current_user = Guardian.Plug.current_resource(conn)
      assert current_user.id == user.id
    end

    test "세션만 있으면 세션의 토큰을 사용한다", %{token: token, user: user} do
      conn =
        conn(:get, "/")
        |> init_test_session(%{guardian_default_token: token})
        |> GuardianPipelineMaybe.call([])

      current_user = Guardian.Plug.current_resource(conn)
      assert current_user.id == user.id
    end

    test "헤더만 있으면 헤더의 토큰을 사용한다", %{token: token, user: user} do
      conn =
        conn(:get, "/")
        |> put_req_header("authorization", "Bearer #{token}")
        |> GuardianPipelineMaybe.call([])

      current_user = Guardian.Plug.current_resource(conn)
      assert current_user.id == user.id
    end
  end

  describe "에러 핸들러 구성" do
    test "Auth.GuardianErrorHandler를 사용한다" do
      opts = GuardianPipelineMaybe.init([])
      assert opts[:error_handler] == Auth.GuardianErrorHandler
    end
  end

  describe "모듈 구성" do
    test "Auth.Guardian 모듈을 사용한다" do
      opts = GuardianPipelineMaybe.init([])
      assert opts[:module] == Auth.Guardian
    end

    test "otp_app이 :auth로 설정되어 있다" do
      opts = GuardianPipelineMaybe.init([])
      assert opts[:otp_app] == :auth
    end
  end
end
