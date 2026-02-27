defmodule DiscussWeb.FallbackControllerTest do
  use DiscussWeb.ConnCase

  test "not_found 에러를 404 JSON으로 반환한다", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> DiscussWeb.FallbackController.call({:error, :not_found})

    assert json_response(conn, 404)
  end

  test "unauthorized 에러를 401 JSON으로 반환한다", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> DiscussWeb.FallbackController.call({:error, :unauthorized})

    assert json_response(conn, 401)
  end
end
