defmodule DiscussWeb.Api.TopicControllerTest do
  use DiscussWeb.ConnCase

  import Discuss.TopicsFixtures

  defp create_api_conn(%{conn: conn}) do
    user = DiscussAuth.AccountsFixtures.user_fixture()
    token = DiscussAuth.Accounts.generate_user_session_token(user)

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer #{token}")

    %{conn: conn, user: user, token: token}
  end

  defp api_conn_without_auth(%{conn: conn}) do
    %{conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "GET /api/topics" do
    setup :api_conn_without_auth

    test "토픽 목록을 JSON으로 반환한다", %{conn: conn} do
      user = DiscussAuth.AccountsFixtures.user_fixture()
      topic_fixture(%{auth_user_id: user.id, title: "API 토픽"})

      conn = get(conn, ~p"/api/topics")
      response = json_response(conn, 200)
      assert is_list(response["data"])
      assert is_map(response["meta"])
    end

    test "페이지 파라미터를 처리한다", %{conn: conn} do
      conn = get(conn, ~p"/api/topics?page=1")
      response = json_response(conn, 200)
      assert response["meta"]["page"] == 1
    end

    test "검색 파라미터를 처리한다", %{conn: conn} do
      conn = get(conn, ~p"/api/topics?search=test")
      assert json_response(conn, 200)
    end
  end

  describe "GET /api/topics/:id" do
    setup :api_conn_without_auth

    test "토픽 상세를 JSON으로 반환한다", %{conn: conn} do
      user = DiscussAuth.AccountsFixtures.user_fixture()
      topic = topic_fixture(%{auth_user_id: user.id, title: "상세 API 토픽"})

      conn = get(conn, ~p"/api/topics/#{topic.id}")
      response = json_response(conn, 200)
      assert response["data"]["id"] == topic.id
      assert response["data"]["title"] == "상세 API 토픽"
    end
  end

  describe "POST /api/topics (비인증)" do
    test "인증 없이 접근하면 401을 반환한다", %{conn: conn} do
      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> post(~p"/api/topics", %{"topic" => %{"title" => "제목"}})

      assert json_response(conn, 401)
    end
  end

  describe "POST /api/topics (인증)" do
    setup :create_api_conn

    test "유효한 데이터로 토픽을 생성한다", %{conn: conn} do
      conn = post(conn, ~p"/api/topics", %{"topic" => %{"title" => "API 생성 토픽"}})
      response = json_response(conn, 201)
      assert response["data"]["title"] == "API 생성 토픽"
    end

    test "유효하지 않은 데이터로 422를 반환한다", %{conn: conn} do
      conn = post(conn, ~p"/api/topics", %{"topic" => %{"title" => ""}})
      assert json_response(conn, 422)
    end
  end

  describe "PUT /api/topics/:id" do
    setup :create_api_conn

    test "소유자가 토픽을 업데이트한다", %{conn: conn, user: user} do
      topic = topic_fixture(%{auth_user_id: user.id})
      conn = put(conn, ~p"/api/topics/#{topic.id}", %{"topic" => %{"title" => "수정됨"}})
      response = json_response(conn, 200)
      assert response["data"]["title"] == "수정됨"
    end

    test "유효하지 않은 데이터로 422를 반환한다", %{conn: conn, user: user} do
      topic = topic_fixture(%{auth_user_id: user.id})
      conn = put(conn, ~p"/api/topics/#{topic.id}", %{"topic" => %{"title" => ""}})
      assert json_response(conn, 422)
    end

    test "소유자가 아니면 403을 반환한다", %{conn: conn} do
      other_user = DiscussAuth.AccountsFixtures.user_fixture()
      topic = topic_fixture(%{auth_user_id: other_user.id})
      conn = put(conn, ~p"/api/topics/#{topic.id}", %{"topic" => %{"title" => "변경"}})
      assert json_response(conn, 403)
    end
  end

  describe "DELETE /api/topics/:id" do
    setup :create_api_conn

    test "소유자가 토픽을 삭제한다", %{conn: conn, user: user} do
      topic = topic_fixture(%{auth_user_id: user.id})
      conn = delete(conn, ~p"/api/topics/#{topic.id}")
      assert response(conn, 204)
    end

    test "소유자가 아니면 403을 반환한다", %{conn: conn} do
      other_user = DiscussAuth.AccountsFixtures.user_fixture()
      topic = topic_fixture(%{auth_user_id: other_user.id})
      conn = delete(conn, ~p"/api/topics/#{topic.id}")
      assert json_response(conn, 403)
    end
  end
end
