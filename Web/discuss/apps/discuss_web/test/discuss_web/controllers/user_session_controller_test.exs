defmodule DiscussWeb.UserSessionControllerTest do
  use DiscussWeb.ConnCase

  import DiscussAuth.AccountsFixtures

  describe "GET /users/log_in" do
    test "로그인 페이지를 렌더링한다", %{conn: conn} do
      conn = get(conn, ~p"/users/log_in")
      assert html_response(conn, 200)
    end
  end

  describe "POST /users/log_in" do
    test "유효한 자격 증명으로 로그인한다", %{conn: conn} do
      user = user_fixture()

      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password()
          }
        })

      assert redirected_to(conn) == ~p"/topics"
    end

    test "잘못된 비밀번호로 에러를 표시한다", %{conn: conn} do
      user = user_fixture()

      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{
            "email" => user.email,
            "password" => "wrong_password"
          }
        })

      response = html_response(conn, 200)
      assert response =~ "올바르지 않습니다"
    end

    test "존재하지 않는 이메일로 에러를 표시한다", %{conn: conn} do
      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{
            "email" => "unknown@example.com",
            "password" => "hello_world!"
          }
        })

      response = html_response(conn, 200)
      assert response =~ "올바르지 않습니다"
    end
  end

  describe "DELETE /users/log_out" do
    test "로그아웃한다", %{conn: conn} do
      user = user_fixture()
      conn = conn |> log_in_user(user)
      conn = delete(conn, ~p"/users/log_out")
      assert redirected_to(conn) == ~p"/"
    end
  end
end
