defmodule DiscussWeb.UserConfirmationControllerTest do
  use DiscussWeb.ConnCase

  import DiscussAuth.AccountsFixtures

  describe "GET /users/confirm" do
    test "이메일 인증 요청 페이지를 렌더링한다", %{conn: conn} do
      conn = get(conn, ~p"/users/confirm")
      assert html_response(conn, 200)
    end
  end

  describe "POST /users/confirm" do
    test "등록된 이메일로 인증 안내를 발송한다", %{conn: conn} do
      user = user_fixture()

      conn =
        post(conn, ~p"/users/confirm", %{
          "user" => %{"email" => user.email}
        })

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "인증 링크"
    end

    test "등록되지 않은 이메일이어도 같은 메시지를 표시한다", %{conn: conn} do
      conn =
        post(conn, ~p"/users/confirm", %{
          "user" => %{"email" => "unknown@example.com"}
        })

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "인증 링크"
    end
  end

  describe "GET /users/confirm/:token" do
    test "인증 확인 페이지를 렌더링한다", %{conn: conn} do
      conn = get(conn, ~p"/users/confirm/some-token")
      assert html_response(conn, 200)
    end
  end

  describe "POST /users/confirm/:token" do
    test "유효하지 않은 토큰으로 에러를 표시한다", %{conn: conn} do
      conn = post(conn, ~p"/users/confirm/invalid-token")
      assert redirected_to(conn) == ~p"/users/confirm"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "유효하지 않거나"
    end

    test "유효한 토큰으로 이메일을 인증한다", %{conn: conn} do
      user = user_fixture()

      {:ok, encoded_token} =
        DiscussAuth.Accounts.deliver_user_confirmation_instructions(
          user,
          &url(~p"/users/confirm/#{&1}")
        )

      conn = post(conn, ~p"/users/confirm/#{encoded_token}")
      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "인증이 완료"
    end
  end
end
