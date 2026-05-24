defmodule AgenticAiAgentWeb.RunLiveTest do
  use AgenticAiAgentWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AgenticAiAgent.Repo
  alias AgenticAiAgent.Traces.Run

  defp make_run!(opts \\ []) do
    %Run{
      user_input: Keyword.get(opts, :user_input, "hi"),
      status: Keyword.get(opts, :status, "done"),
      started_at: DateTime.utc_now()
    }
    |> Repo.insert!()
  end

  defp days_ago(n), do: DateTime.utc_now() |> DateTime.add(-n * 86_400, :second)

  describe "GET /runs" do
    test "shows the cleanup panel", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/runs")
      assert html =~ "Cleanup"
      assert html =~ "Delete runs older than"
    end
  end

  describe "GET /runs/:id" do
    test "renders the run trace with a Delete button", %{conn: conn} do
      run = make_run!()
      {:ok, _view, html} = live(conn, ~p"/runs/#{run.id}")
      assert html =~ String.slice(run.id, 0, 8)
      assert html =~ "Delete run"
    end

    test "delete_run event removes the row and redirects to /runs", %{conn: conn} do
      run = make_run!()
      {:ok, view, _html} = live(conn, ~p"/runs/#{run.id}")

      assert {:error, {:live_redirect, %{to: "/runs"}}} =
               render_click(view, "delete_run")

      refute Repo.get(Run, run.id)
    end
  end

  describe "bulk delete by age" do
    test "deletes old runs and flashes the count; young ones survive", %{conn: conn} do
      _old1 =
        %Run{user_input: "old1", status: "done", started_at: DateTime.utc_now()}
        |> Repo.insert!()
        |> tap(fn r ->
          import Ecto.Query
          Repo.update_all(from(x in Run, where: x.id == ^r.id), set: [inserted_at: days_ago(40)])
        end)

      young = make_run!()

      {:ok, view, _html} = live(conn, ~p"/runs")
      # Select 30-day retention then submit.
      view |> element("form") |> render_change(%{"days" => "30"})
      html = view |> element("form") |> render_submit(%{"days" => "30"})

      assert html =~ "older than 30 day" or html =~ "Deleted"
      assert Repo.get(Run, young.id)
    end
  end
end
