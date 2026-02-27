defmodule DiscussWeb.AdminUserControllerTest do
  use DiscussWeb.ConnCase

  import Discuss.AdminFixtures

  defp create_admin(%{conn: conn}) do
    user = DiscussAuth.AccountsFixtures.user_fixture()
    conn = log_in_user(conn, user)

    admin_user_fixture(%{
      "auth_user_id" => user.id,
      "name" => "관리자",
      "role" => "admin"
    })

    %{conn: conn, user: user}
  end

  describe "비인증 사용자" do
    test "관리자 페이지에 접근하면 로그인으로 리다이렉트된다", %{conn: conn} do
      conn = get(conn, ~p"/admin/users")
      assert redirected_to(conn) == ~p"/users/log_in"
    end
  end

  describe "인증되었지만 관리자가 아닌 사용자" do
    setup :register_and_log_in_user

    test "관리자 페이지에 접근하면 홈으로 리다이렉트된다", %{conn: conn} do
      conn = get(conn, ~p"/admin/users")
      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "관리자 권한"
    end
  end

  describe "관리자 사용자 - index" do
    setup :create_admin

    test "사용자 목록을 렌더링한다", %{conn: conn} do
      conn = get(conn, ~p"/admin/users")
      assert html_response(conn, 200)
    end
  end

  describe "관리자 사용자 - new" do
    setup :create_admin

    test "새 사용자 폼을 렌더링한다", %{conn: conn} do
      conn = get(conn, ~p"/admin/users/new")
      assert html_response(conn, 200)
    end
  end

  describe "관리자 사용자 - create" do
    setup :create_admin

    test "유효한 데이터로 사용자를 생성한다", %{conn: conn} do
      conn =
        post(conn, ~p"/admin/users", %{
          "user" => %{
            "name" => "새관리자",
            "email" => "new_admin@example.com",
            "role" => "admin",
            "address" => "서울시"
          }
        })

      assert redirected_to(conn) == ~p"/admin/users"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "생성되었습니다"
    end

    test "유효하지 않은 데이터로 에러를 표시한다", %{conn: conn} do
      conn = post(conn, ~p"/admin/users", %{"user" => %{}})
      assert html_response(conn, 200)
    end
  end

  describe "관리자 사용자 - show" do
    setup :create_admin

    test "사용자 상세를 렌더링한다", %{conn: conn} do
      admin = admin_user_fixture()
      conn = get(conn, ~p"/admin/users/#{admin.id}")
      assert html_response(conn, 200)
    end
  end

  describe "관리자 사용자 - edit" do
    setup :create_admin

    test "사용자 수정 폼을 렌더링한다", %{conn: conn} do
      admin = admin_user_fixture()
      conn = get(conn, ~p"/admin/users/#{admin.id}/edit")
      assert html_response(conn, 200)
    end
  end

  describe "관리자 사용자 - update" do
    setup :create_admin

    test "유효한 데이터로 사용자를 업데이트한다", %{conn: conn} do
      admin = admin_user_fixture()

      conn =
        put(conn, ~p"/admin/users/#{admin.id}", %{
          "user" => %{"name" => "수정된 관리자"}
        })

      assert redirected_to(conn) == ~p"/admin/users"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "업데이트되었습니다"
    end

    test "유효하지 않은 데이터로 에러를 표시한다", %{conn: conn} do
      admin = admin_user_fixture()

      conn =
        put(conn, ~p"/admin/users/#{admin.id}", %{
          "user" => %{"name" => ""}
        })

      assert html_response(conn, 200)
    end
  end

  describe "관리자 사용자 - delete" do
    setup :create_admin

    test "사용자를 삭제한다", %{conn: conn} do
      admin = admin_user_fixture()
      conn = delete(conn, ~p"/admin/users/#{admin.id}")
      assert redirected_to(conn) == ~p"/admin/users"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "삭제되었습니다"
    end
  end
end
