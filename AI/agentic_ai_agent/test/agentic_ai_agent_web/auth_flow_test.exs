defmodule AgenticAiAgentWeb.AuthFlowTest do
  use AgenticAiAgentWeb.ConnCase, async: false

  alias AgenticAiAgent.Accounts

  @tag :unauthenticated
  test "redirects protected pages to login", %{conn: conn} do
    conn = get(conn, ~p"/chat")
    assert redirected_to(conn) == ~p"/login"
  end

  @tag :unauthenticated
  test "registers and logs in", %{conn: conn} do
    conn =
      post(conn, ~p"/register", %{
        "user" => %{
          "email" => "new@example.com",
          "display_name" => "New User",
          "password" => "password123"
        }
      })

    assert redirected_to(conn) == ~p"/chat"
    assert get_session(conn, :user_id)
    assert Accounts.get_user_by_email("new@example.com")
  end

  @tag :unauthenticated
  test "logs in with valid credentials", %{conn: conn} do
    {:ok, _user} =
      Accounts.create_user(%{
        email: "login@example.com",
        display_name: "Login User",
        password: "password123",
        preferred_locale: "ko",
        preferred_theme: "dark"
      })

    conn =
      post(conn, ~p"/login", %{
        "user" => %{"email" => "login@example.com", "password" => "password123"}
      })

    assert redirected_to(conn) == ~p"/chat"
    assert get_session(conn, :user_id)
    assert get_session(conn, :locale) == "ko"
    assert get_session(conn, :theme) == "dark"
  end

  test "stores the signed-in user's theme preference", %{conn: conn, current_user: user} do
    conn = put(conn, ~p"/preferences/theme", %{"theme" => "dark"})

    assert response(conn, 204) == ""
    assert Accounts.get_user(user.id).preferred_theme == "dark"
  end
end
