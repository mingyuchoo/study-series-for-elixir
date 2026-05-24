defmodule AgenticAiAgentWeb.ToolLiveTest do
  # async: false — Tools.Registry is a global singleton.
  use AgenticAiAgentWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AgenticAiAgent.Tools.Registry, as: TR

  setup do
    on_exit(fn ->
      # Restore calculator to its built-in defaults so concurrent or later
      # tests don't see leftover overrides.
      _ = TR.update_spec("calculator", %{"risk_level" => "low", "enabled" => true})
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
