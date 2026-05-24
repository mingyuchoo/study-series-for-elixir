defmodule AgenticAiAgentWeb.ProfileLiveTest do
  use AgenticAiAgentWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AgenticAiAgent.Accounts

  test "updates the signed-in user's profile", %{conn: conn, current_user: user} do
    {:ok, view, html} = live(conn, ~p"/profile")
    assert html =~ "Profile"
    refute html =~ "Profile 01"

    avatar =
      file_input(view, "form", :avatar, [
        %{
          name: "avatar.png",
          content:
            Base.decode64!(
              "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="
            ),
          type: "image/png"
        }
      ])

    render_upload(avatar, "avatar.png")

    html =
      view
      |> form("form", %{
        "user" => %{
          "display_name" => "Updated User",
          "preferred_locale" => "ko",
          "preferred_theme" => "dark"
        }
      })
      |> render_submit()

    assert html =~ "프로필을 저장했습니다."

    updated = Accounts.get_user(user.id)
    assert updated.display_name == "Updated User"
    assert updated.avatar_path =~ ~r|^/uploads/profiles/.+\.png$|
    assert updated.preferred_locale == "ko"
    assert updated.preferred_theme == "dark"

    uploaded_file =
      Path.join([
        File.cwd!(),
        "priv/static",
        String.trim_leading(updated.avatar_path, "/")
      ])

    File.rm(uploaded_file)
  end
end
