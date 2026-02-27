defmodule DiscussWeb.UserRegistrationControllerTest do
  use DiscussWeb.ConnCase

  import DiscussAuth.AccountsFixtures

  describe "GET /users/register" do
    test "회원가입 페이지를 렌더링한다", %{conn: conn} do
      conn = get(conn, ~p"/users/register")
      assert html_response(conn, 200)
    end

    test "이미 로그인된 사용자는 리다이렉트된다", %{conn: conn} do
      user = user_fixture()
      conn = conn |> log_in_user(user) |> get(~p"/users/register")
      assert redirected_to(conn) == ~p"/topics"
    end
  end

  describe "POST /users/register" do
    test "유효한 데이터로 사용자를 생성하고 리다이렉트된다", %{conn: conn} do
      email = unique_user_email()

      conn =
        post(conn, ~p"/users/register", %{
          "user" => %{"email" => email, "password" => valid_user_password()}
        })

      assert redirected_to(conn) == ~p"/topics"
    end

    test "유효하지 않은 데이터로 에러를 표시한다", %{conn: conn} do
      conn =
        post(conn, ~p"/users/register", %{
          "user" => %{"email" => "invalid", "password" => "short"}
        })

      assert html_response(conn, 200)
    end
  end
end
