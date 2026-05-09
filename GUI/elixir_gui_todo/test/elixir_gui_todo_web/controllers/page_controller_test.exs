defmodule ElixirGuiTodoWeb.PageControllerTest do
  use ElixirGuiTodoWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Elixir Todo"
  end
end
