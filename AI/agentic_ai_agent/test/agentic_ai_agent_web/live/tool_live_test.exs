defmodule AgenticAiAgentWeb.ToolLiveTest do
  # async: false — Tools.Registry is a global singleton.
  use AgenticAiAgentWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AgenticAiAgent.Tools.Registry, as: TR

  setup do
    on_exit(fn ->
      # Best-effort: restore calculator defaults so concurrent / later tests
      # don't see leftover overrides. The Registry GenServer holds its own
      # checked-out connection; if the test's sandbox is already torn down
      # the call may fail — that's tolerable for cleanup so we swallow it.
      try do
        TR.update_spec("calculator", %{"risk_level" => "low", "enabled" => true})
      catch
        :exit, _ -> :ok
      end
    end)

    :ok
  end

  describe "GET /tools" do
    test "lists registered tools with their effective risk level", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/tools")
      assert html =~ "calculator"
      assert html =~ "python_exec"
    end
  end

  describe "toggle_enabled event" do
    test "flips enabled and surfaces a flash; descriptors reflect immediately", %{conn: conn} do
      assert TR.enabled?("calculator")
      {:ok, view, _html} = live(conn, ~p"/tools")

      html = render_click(view, "toggle_enabled", %{"name" => "calculator"})

      refute TR.enabled?("calculator")
      assert html =~ "Disabled calculator" or html =~ "disabled"
      refute Enum.any?(TR.descriptors(), &(&1["name"] == "calculator"))
    end
  end
end
