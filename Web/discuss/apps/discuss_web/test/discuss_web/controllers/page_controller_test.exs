defmodule DiscussWeb.PageControllerTest do
  use DiscussWeb.ConnCase

  describe "GET /" do
    test "홈 페이지를 렌더링한다", %{conn: conn} do
      conn = get(conn, ~p"/")
      assert html_response(conn, 200)
    end
  end
end
