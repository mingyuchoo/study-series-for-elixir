defmodule AgenticAiAgentWeb.ImprovementLiveTest do
  use AgenticAiAgentWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AgenticAiAgent.Improver.Proposal
  alias AgenticAiAgent.Repo

  test "renders staged proposals without a staging slug", %{conn: conn} do
    proposal =
      Repo.insert!(%Proposal{
        kind: "tool_policy_change",
        target: "default",
        proposed_change: %{"allow" => ["calculator"]},
        justification: "test proposal",
        status: "staged_passed",
        staging_slug: nil
      })

    {:ok, _view, html} = live(conn, ~p"/improvements")

    assert html =~ String.slice(proposal.id, 0, 8)
    assert html =~ "test proposal"
  end
end
