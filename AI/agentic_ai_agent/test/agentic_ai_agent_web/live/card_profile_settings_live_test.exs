defmodule AgenticAiAgentWeb.CardProfileSettingsLiveTest do
  use AgenticAiAgentWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AgenticAiAgent.Design

  @slug "profile-card-#{System.unique_integer([:positive])}"

  setup do
    yaml = """
    slug: #{@slug}
    name: Profile Card
    metadata:
      agent_avatar_path: /images/avatars/avatar-01.png
    """

    {:ok, %{card: card}} = Design.save_card_source(@slug, yaml, reason: "seed profile test")

    on_exit(fn ->
      case Design.card_source_path(@slug) do
        nil -> :ok
        path -> _ = File.rm(path)
      end
    end)

    {:ok, card: card}
  end

  test "saves the selected profile image to card metadata", %{conn: conn, card: card} do
    {:ok, view, html} = live(conn, ~p"/cards/#{card.id}/profile")
    assert html =~ "Profile settings"
    assert html =~ "/images/avatars/avatar-01.png"

    html =
      view
      |> form("#profile-settings-form", %{
        "agent_avatar_path" => "/images/avatars/avatar-04.png"
      })
      |> render_submit()

    assert html =~ "Profile settings saved."

    source = File.read!(Design.card_source_path(@slug))
    assert source =~ ~s(agent_avatar_path: "/images/avatars/avatar-04.png")

    assert Design.get_card_by_slug(@slug).metadata["agent_avatar_path"] ==
             "/images/avatars/avatar-04.png"
  end
end
