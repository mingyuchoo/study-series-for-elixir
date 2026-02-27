defmodule DiscussWeb.UserAuthTest do
  use DiscussWeb.ConnCase

  alias DiscussWeb.UserAuth
  import DiscussAuth.AccountsFixtures

  describe "fetch_current_user/2" do
    test "세션에 토큰이 있으면 사용자를 할당한다", %{conn: conn} do
      user = user_fixture()
      conn = conn |> log_in_user(user) |> UserAuth.fetch_current_user([])
      assert conn.assigns.current_user.id == user.id
    end

    test "세션에 토큰이 없으면 nil을 할당한다", %{conn: conn} do
      conn =
        conn
        |> Phoenix.ConnTest.init_test_session(%{})
        |> UserAuth.fetch_current_user([])

      assert is_nil(conn.assigns.current_user)
    end

    test "remember_me 쿠키로 사용자를 할당한다", %{conn: conn} do
      user = user_fixture()
      token = DiscussAuth.Accounts.generate_user_session_token(user)

      key_base = DiscussWeb.Endpoint.config(:secret_key_base)
      signed = Plug.Crypto.sign(key_base, "_discuss_web_user_remember_me_cookie", token)

      conn =
        conn
        |> Map.put(:secret_key_base, key_base)
        |> Phoenix.ConnTest.init_test_session(%{})
        |> put_req_cookie("_discuss_web_user_remember_me", signed)
        |> UserAuth.fetch_current_user([])

      assert conn.assigns.current_user.id == user.id
    end
  end

  describe "require_authenticated_user/2" do
    test "인증된 사용자는 통과한다", %{conn: conn} do
      user = user_fixture()

      conn =
        conn
        |> log_in_user(user)
        |> UserAuth.fetch_current_user([])
        |> UserAuth.require_authenticated_user([])

      refute conn.halted
    end

    test "비인증 사용자는 로그인 페이지로 리다이렉트된다", %{conn: conn} do
      conn =
        conn
        |> Phoenix.ConnTest.init_test_session(%{})
        |> setup_flash()
        |> UserAuth.fetch_current_user([])
        |> UserAuth.require_authenticated_user([])

      assert conn.halted
      assert redirected_to(conn) == ~p"/users/log_in"
    end

    test "GET 요청은 return_to를 저장한다", %{conn: conn} do
      # 인증 없이 보호된 경로에 GET 요청을 보내면 return_to가 저장된다
      conn = get(conn, ~p"/topics")
      assert redirected_to(conn) == ~p"/users/log_in"
      assert get_session(conn, :user_return_to) == "/topics"
    end

    test "POST 요청은 return_to를 저장하지 않는다", %{conn: conn} do
      conn = post(conn, ~p"/topics", topic: %{title: "test"})
      assert redirected_to(conn) == ~p"/users/log_in"
      refute get_session(conn, :user_return_to)
    end
  end

  describe "redirect_if_user_is_authenticated/2" do
    test "인증된 사용자는 토픽 목록으로 리다이렉트된다", %{conn: conn} do
      user = user_fixture()

      conn =
        conn
        |> log_in_user(user)
        |> UserAuth.fetch_current_user([])
        |> UserAuth.redirect_if_user_is_authenticated([])

      assert conn.halted
      assert redirected_to(conn) == ~p"/topics"
    end

    test "비인증 사용자는 통과한다", %{conn: conn} do
      conn =
        conn
        |> Phoenix.ConnTest.init_test_session(%{})
        |> UserAuth.fetch_current_user([])
        |> UserAuth.redirect_if_user_is_authenticated([])

      refute conn.halted
    end
  end

  describe "require_admin_user/2" do
    test "관리자가 아니면 홈으로 리다이렉트된다", %{conn: conn} do
      user = user_fixture()

      conn =
        conn
        |> log_in_user(user)
        |> UserAuth.fetch_current_user([])
        |> setup_flash()
        |> UserAuth.require_admin_user([])

      assert conn.halted
      assert redirected_to(conn) == ~p"/"
    end

    test "관리자이면 통과한다", %{conn: conn} do
      user = user_fixture()

      Discuss.Admin.create_user(%{
        "name" => "관리자",
        "email" => user.email,
        "role" => "admin",
        "address" => "서울",
        "auth_user_id" => user.id
      })

      conn =
        conn
        |> log_in_user(user)
        |> UserAuth.fetch_current_user([])
        |> setup_flash()
        |> UserAuth.require_admin_user([])

      refute conn.halted
    end
  end

  describe "fetch_api_user/2" do
    test "유효한 Bearer 토큰으로 사용자를 할당한다", %{conn: conn} do
      user = user_fixture()
      token = DiscussAuth.Accounts.generate_user_session_token(user)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> UserAuth.fetch_api_user([])

      assert conn.assigns.current_user.id == user.id
    end

    test "토큰이 없으면 nil을 할당한다", %{conn: conn} do
      conn = UserAuth.fetch_api_user(conn, [])
      assert is_nil(conn.assigns.current_user)
    end

    test "잘못된 토큰이면 nil을 할당한다", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer invalid_token")
        |> UserAuth.fetch_api_user([])

      assert is_nil(conn.assigns.current_user)
    end
  end

  describe "require_api_user/2" do
    test "인증된 API 사용자는 통과한다", %{conn: conn} do
      user = user_fixture()

      conn =
        conn
        |> assign(:current_user, user)
        |> UserAuth.require_api_user([])

      refute conn.halted
    end

    test "비인증 API 사용자는 401을 반환한다", %{conn: conn} do
      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> assign(:current_user, nil)
        |> UserAuth.require_api_user([])

      assert conn.halted
      assert conn.status == 401
    end
  end

  describe "log_in_user/3" do
    test "사용자를 로그인시키고 토픽 목록으로 리다이렉트한다", %{conn: conn} do
      user = user_fixture()

      conn =
        conn
        |> Phoenix.ConnTest.init_test_session(%{})
        |> setup_flash()
        |> UserAuth.log_in_user(user)

      assert redirected_to(conn) == ~p"/topics"
      assert get_session(conn, :user_token)
    end

    test "user_return_to가 있으면 해당 경로로 리다이렉트한다", %{conn: conn} do
      user = user_fixture()

      conn =
        conn
        |> Phoenix.ConnTest.init_test_session(%{user_return_to: "/topics/1"})
        |> setup_flash()
        |> UserAuth.log_in_user(user)

      assert redirected_to(conn) == "/topics/1"
    end

    test "remember_me가 true이면 쿠키를 설정한다", %{conn: conn} do
      user = user_fixture()

      conn =
        conn
        |> Phoenix.ConnTest.init_test_session(%{})
        |> setup_flash()
        |> UserAuth.log_in_user(user, %{"remember_me" => "true"})

      assert conn.resp_cookies["_discuss_web_user_remember_me"]
    end
  end

  describe "log_out_user/1" do
    test "세션을 정리하고 홈으로 리다이렉트한다", %{conn: conn} do
      user = user_fixture()

      conn =
        conn
        |> log_in_user(user)
        |> setup_flash()
        |> UserAuth.log_out_user()

      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
    end

    test "live_socket_id가 있으면 disconnect를 broadcast한다", %{conn: conn} do
      user = user_fixture()
      token = DiscussAuth.Accounts.generate_user_session_token(user)
      live_socket_id = "users_sessions:#{Base.url_encode64(token)}"

      DiscussWeb.Endpoint.subscribe(live_socket_id)

      conn
      |> Phoenix.ConnTest.init_test_session(%{
        user_token: token,
        live_socket_id: live_socket_id
      })
      |> setup_flash()
      |> UserAuth.log_out_user()

      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}
    end
  end

  defp setup_flash(conn) do
    conn
    |> Phoenix.ConnTest.bypass_through(DiscussWeb.Router, [:browser])
    |> get("/")
  end
end
