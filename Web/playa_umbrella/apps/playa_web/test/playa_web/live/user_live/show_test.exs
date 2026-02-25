defmodule PlayaWeb.UserLive.ShowTest do
  use PlayaWeb.ConnCase

  import Phoenix.LiveViewTest
  import Playa.AccountsFixtures

  describe "Show" do
    setup :register_and_log_in_user

    setup _context do
      # unique한 role 이름 생성
      role = role_fixture(%{abbr: "ADMIN"})
      %{role: role}
    end

    test "displays user information", %{conn: conn, user: user} do
      {:ok, _show_live, html} = live(conn, ~p"/accounts/users/#{user.id}")

      assert html =~ "Show User"
      assert html =~ user.email
    end

    test "deletes user in listing", %{conn: conn, user: user} do
      {:ok, show_live, html} = live(conn, ~p"/accounts/users/#{user.id}")

      # Header에 trash 아이콘이 있는지 확인
      assert html =~ "hero-trash"

      # Header의 actions 내에서 delete 링크 찾기 (trash 아이콘 포함)
      assert show_live
             |> element("header a[data-confirm]")
             |> render_click()

      assert_redirect(show_live, "/accounts/users")
    end

    test "saves new role assignment", %{conn: conn, user: user, role: role} do
      {:ok, show_live, _html} = live(conn, ~p"/accounts/users/#{user.id}")

      assert show_live
             |> form("#role_form", role_user: %{role_id: role.id, user_id: user.id})
             |> render_submit()

      html = render(show_live)
      assert html =~ role.name
    end

    test "deletes role assignment", %{conn: conn, user: user, role: role} do
      # 먼저 역할 할당
      {:ok, _role_user} = Playa.Accounts.create_role_user(%{role_id: role.id, user_id: user.id})

      {:ok, show_live, html} = live(conn, ~p"/accounts/users/#{user.id}")

      # 역할이 표시되는지 확인
      assert html =~ role.name
      assert has_element?(show_live, "#my_roles-#{role.id}")

      # 특정 role의 row에서 삭제 링크 찾기
      assert show_live
             |> element("#my_roles-#{role.id} a[data-confirm]")
             |> render_click()

      # 역할이 DOM에서 완전히 제거되었는지 확인
      refute has_element?(show_live, "#my_roles-#{role.id}")
    end

    test "validates role assignment form", %{conn: conn, user: user} do
      {:ok, show_live, _html} = live(conn, ~p"/accounts/users/#{user.id}")

      # role_id 없이 제출하면 실패해야 함
      result =
        show_live
        |> form("#role_form", role_user: %{role_id: "", user_id: user.id})
        |> render_submit()

      # form이 여전히 표시되어야 함 (제출되지 않음)
      assert result =~ "role_form"
    end
  end

  describe "Edit" do
    setup :register_and_log_in_user

    test "displays edit form", %{conn: conn, user: user} do
      {:ok, _edit_live, html} = live(conn, ~p"/accounts/users/#{user.id}/edit")

      assert html =~ "Edit User"
      assert html =~ user.email
    end

    test "updates user successfully", %{conn: conn, user: user} do
      {:ok, edit_live, _html} = live(conn, ~p"/accounts/users/#{user.id}/edit")

      new_nickname = "updated_nickname"

      assert edit_live
             |> form("#user-form", user: %{nickname: new_nickname})
             |> render_submit()

      html = render(edit_live)
      assert html =~ new_nickname
    end
  end
end
