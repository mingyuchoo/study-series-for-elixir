defmodule AgenticAiAgentWeb.PageControllerTest do
  use AgenticAiAgentWeb.ConnCase

  test "GET / renders the home dashboard with the app shell", %{conn: conn} do
    body = html_response(get(conn, ~p"/"), 200)

    # Stable elements: the brand mark in the layout shell and at least one
    # dashboard card link the home page wires up.
    assert body =~ "Agentic AI Agent"
    assert body =~ ~s|href="/chat"|
  end
end
