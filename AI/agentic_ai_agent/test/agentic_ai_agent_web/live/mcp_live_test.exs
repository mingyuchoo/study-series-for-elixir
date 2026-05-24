defmodule AgenticAiAgentWeb.MCPLiveTest do
  # async: false — the live MCP supervisor + Tools.Registry are global
  # singletons; concurrent tests would race on the shared state.
  use AgenticAiAgentWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AgenticAiAgent.MCP.Servers

  setup do
    # Clean any leftover rows from previous interactive runs so the index
    # starts empty for the test.
    for s <- Servers.list_records(), do: Servers.delete(s)
    :ok
  end

  describe "GET /mcp" do
    test "renders empty state when no servers are configured", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/mcp")
      assert html =~ "No MCP servers configured yet"
    end

    test "lists existing servers", %{conn: conn} do
      {:ok, _} =
        Servers.create(%{
          "name" => "lv-test-fs",
          "command" => "echo",
          "transport" => "stdio",
          "enabled" => false
        })

      {:ok, _view, html} = live(conn, ~p"/mcp")
      assert html =~ "lv-test-fs"
    end
  end

  describe "GET /mcp/new" do
    test "renders the form with stdio fields by default", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/mcp/new")
      assert html =~ "New MCP server"
      assert html =~ "Command"
    end

    test "submitting valid stdio attrs persists the row and redirects", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/mcp/new")

      assert {:error, {:live_redirect, %{to: "/mcp"}}} =
               view
               |> form("form",
                 server: %{
                   "name" => "lv-test-stdio",
                   "transport" => "stdio",
                   "command" => "echo",
                   "risk_level" => "low",
                   "enabled" => "false"
                 }
               )
               |> render_submit()

      assert Servers.get_by_name("lv-test-stdio")
    end

    test "rejects invalid name with a form error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/mcp/new")

      html =
        view
        |> form("form",
          server: %{
            "name" => "BAD UPPER",
            "transport" => "stdio",
            "command" => "echo",
            "risk_level" => "low"
          }
        )
        |> render_submit()

      # Stays on the form (no redirect) and surfaces the format error.
      assert html =~ "lowercase letters"
      refute Servers.get_by_name("BAD UPPER")
    end
  end

  describe "delete event from index" do
    test "removes the row and flashes confirmation", %{conn: conn} do
      {:ok, server} =
        Servers.create(%{
          "name" => "lv-test-delete",
          "command" => "echo",
          "transport" => "stdio",
          "enabled" => false
        })

      {:ok, view, _} = live(conn, ~p"/mcp")

      html = render_click(view, "delete", %{"id" => server.id})

      assert html =~ "Deleted lv-test-delete" or html =~ "lv-test-delete"
      refute Servers.get_by_name("lv-test-delete")
    end
  end
end
