defmodule DiscussWeb.UserPasswordResetControllerTest do
  use DiscussWeb.ConnCase

  import DiscussAuth.AccountsFixtures

  describe "GET /users/reset_password" do
    test "비밀번호 재설정 요청 페이지를 렌더링한다", %{conn: conn} do
      conn = get(conn, ~p"/users/reset_password")
      assert html_response(conn, 200)
    end
  end

  describe "POST /users/reset_password" do
    test "등록된 이메일로 재설정 안내를 발송한다", %{conn: conn} do
      user = user_fixture()

      conn =
        post(conn, ~p"/users/reset_password", %{
          "user" => %{"email" => user.email}
        })

      assert redirected_to(conn) == ~p"/users/log_in"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "재설정 링크"
    end

    test "등록되지 않은 이메일이어도 같은 메시지를 표시한다", %{conn: conn} do
      conn =
        post(conn, ~p"/users/reset_password", %{
          "user" => %{"email" => "unknown@example.com"}
        })

      assert redirected_to(conn) == ~p"/users/log_in"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "재설정 링크"
    end
  end

  describe "GET /users/reset_password/:token" do
    test "유효하지 않은 토큰으로 리다이렉트된다", %{conn: conn} do
      conn = get(conn, ~p"/users/reset_password/invalid-token")
      assert redirected_to(conn) == ~p"/users/reset_password"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "유효하지 않거나"
    end

    test "유효한 토큰으로 비밀번호 재설정 폼을 렌더링한다", %{conn: conn} do
      user = user_fixture()

      {:ok, encoded_token} =
        DiscussAuth.Accounts.deliver_user_reset_password_instructions(
          user,
          &url(~p"/users/reset_password/#{&1}")
        )

      conn = get(conn, ~p"/users/reset_password/#{encoded_token}")
      assert html_response(conn, 200)
    end
  end

  describe "PUT /users/reset_password/:token" do
    test "유효하지 않은 토큰으로 리다이렉트된다", %{conn: conn} do
      conn =
        put(conn, ~p"/users/reset_password/invalid-token", %{
          "user" => %{
            "password" => "new_password!",
            "password_confirmation" => "new_password!"
          }
        })

      assert redirected_to(conn) == ~p"/users/reset_password"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "유효하지 않거나"
    end

    test "유효한 토큰과 유효한 비밀번호로 비밀번호를 재설정한다", %{conn: conn} do
      user = user_fixture()

      {:ok, encoded_token} =
        DiscussAuth.Accounts.deliver_user_reset_password_instructions(
          user,
          &url(~p"/users/reset_password/#{&1}")
        )

      conn =
        put(conn, ~p"/users/reset_password/#{encoded_token}", %{
          "user" => %{
            "password" => "new_valid_password!",
            "password_confirmation" => "new_valid_password!"
          }
        })

      assert redirected_to(conn) == ~p"/users/log_in"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "성공적으로"
    end

    test "유효한 토큰이지만 유효하지 않은 비밀번호로 에러를 표시한다", %{conn: conn} do
      user = user_fixture()

      {:ok, encoded_token} =
        DiscussAuth.Accounts.deliver_user_reset_password_instructions(
          user,
          &url(~p"/users/reset_password/#{&1}")
        )

      conn =
        put(conn, ~p"/users/reset_password/#{encoded_token}", %{
          "user" => %{
            "password" => "short",
            "password_confirmation" => "short"
          }
        })

      assert html_response(conn, 200)
    end
  end
end
