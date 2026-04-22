defmodule WebWeb.PageControllerTest do
  use WebWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Agentic AI"
  end
end
