defmodule DiscussWeb.TopicControllerTest do
  use DiscussWeb.ConnCase

  import Discuss.TopicsFixtures

  describe "비인증 사용자" do
    test "토픽 목록에 접근하면 로그인 페이지로 리다이렉트된다", %{conn: conn} do
      conn = get(conn, ~p"/topics")
      assert redirected_to(conn) == ~p"/users/log_in"
    end

    test "새 토픽 페이지에 접근하면 로그인 페이지로 리다이렉트된다", %{conn: conn} do
      conn = get(conn, ~p"/topics/new")
      assert redirected_to(conn) == ~p"/users/log_in"
    end
  end

  describe "인증된 사용자 - index" do
    setup :register_and_log_in_user

    test "토픽 목록을 렌더링한다", %{conn: conn} do
      conn = get(conn, ~p"/topics")
      assert html_response(conn, 200) =~ "토픽 목록"
    end

    test "토픽이 있으면 목록에 표시된다", %{conn: conn, user: user} do
      topic = topic_fixture(%{auth_user_id: user.id, title: "표시될 토픽"})
      conn = get(conn, ~p"/topics")
      assert html_response(conn, 200) =~ topic.title
    end

    test "검색 파라미터로 필터링한다", %{conn: conn, user: user} do
      topic_fixture(%{auth_user_id: user.id, title: "엘릭서 토픽"})
      topic_fixture(%{auth_user_id: user.id, title: "피닉스 토픽"})

      conn = get(conn, ~p"/topics?search=엘릭서")
      response = html_response(conn, 200)
      assert response =~ "엘릭서 토픽"
      refute response =~ "피닉스 토픽"
    end

    test "내 토픽만 필터링한다", %{conn: conn, user: user} do
      topic_fixture(%{auth_user_id: user.id, title: "내 토픽"})

      conn = get(conn, ~p"/topics?my_topics=true")
      assert html_response(conn, 200) =~ "내 토픽"
    end

    test "페이지 파라미터를 처리한다", %{conn: conn} do
      conn = get(conn, ~p"/topics?page=1")
      assert html_response(conn, 200)
    end
  end

  describe "인증된 사용자 - new" do
    setup :register_and_log_in_user

    test "새 토픽 폼을 렌더링한다", %{conn: conn} do
      conn = get(conn, ~p"/topics/new")
      assert html_response(conn, 200) =~ "새 토픽 생성"
    end

    test "새 토픽 폼에서 유효성 검증 에러가 바로 표시되지 않는다", %{conn: conn} do
      conn = get(conn, ~p"/topics/new")
      response = html_response(conn, 200)
      refute response =~ "can&#39;t be blank"
      refute response =~ "can't be blank"
    end
  end

  describe "인증된 사용자 - create" do
    setup :register_and_log_in_user

    test "유효한 데이터로 토픽을 생성하고 리다이렉트된다", %{conn: conn} do
      conn = post(conn, ~p"/topics", topic: %{title: "새로운 토픽"})

      assert redirected_to(conn) == ~p"/topics"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "생성되었습니다"
    end

    test "유효하지 않은 데이터로 에러를 표시한다", %{conn: conn} do
      conn = post(conn, ~p"/topics", topic: %{title: ""})
      assert html_response(conn, 200) =~ "새 토픽 생성"
    end
  end

  describe "인증된 사용자 - show" do
    setup :register_and_log_in_user

    test "토픽 상세를 렌더링한다", %{conn: conn, user: user} do
      topic = topic_fixture(%{auth_user_id: user.id, title: "상세 토픽"})
      conn = get(conn, ~p"/topics/#{topic.id}")
      assert html_response(conn, 200) =~ "상세 토픽"
    end
  end

  describe "인증된 사용자 - edit" do
    setup :register_and_log_in_user

    test "소유자가 토픽 수정 폼을 렌더링한다", %{conn: conn, user: user} do
      topic = topic_fixture(%{auth_user_id: user.id, title: "수정할 토픽"})
      conn = get(conn, ~p"/topics/#{topic.id}/edit")
      assert html_response(conn, 200) =~ "토픽 수정"
    end

    test "소유자가 아니면 리다이렉트된다", %{conn: conn} do
      other_user = DiscussAuth.AccountsFixtures.user_fixture()
      topic = topic_fixture(%{auth_user_id: other_user.id})
      conn = get(conn, ~p"/topics/#{topic.id}/edit")
      assert redirected_to(conn) == ~p"/topics"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "접근 권한"
    end
  end

  describe "인증된 사용자 - update" do
    setup :register_and_log_in_user

    test "유효한 데이터로 토픽을 업데이트한다", %{conn: conn, user: user} do
      topic = topic_fixture(%{auth_user_id: user.id})
      conn = put(conn, ~p"/topics/#{topic.id}", topic: %{title: "업데이트된 제목"})
      assert redirected_to(conn) == ~p"/topics"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "업데이트되었습니다"
    end

    test "유효하지 않은 데이터로 에러를 표시한다", %{conn: conn, user: user} do
      topic = topic_fixture(%{auth_user_id: user.id})
      conn = put(conn, ~p"/topics/#{topic.id}", topic: %{title: ""})
      assert html_response(conn, 200) =~ "토픽 수정"
    end

    test "소유자가 아니면 리다이렉트된다", %{conn: conn} do
      other_user = DiscussAuth.AccountsFixtures.user_fixture()
      topic = topic_fixture(%{auth_user_id: other_user.id})
      conn = put(conn, ~p"/topics/#{topic.id}", topic: %{title: "변경"})
      assert redirected_to(conn) == ~p"/topics"
    end
  end

  describe "인증된 사용자 - delete" do
    setup :register_and_log_in_user

    test "소유자가 토픽을 삭제한다", %{conn: conn, user: user} do
      topic = topic_fixture(%{auth_user_id: user.id})
      conn = delete(conn, ~p"/topics/#{topic.id}")
      assert redirected_to(conn) == ~p"/topics"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "삭제되었습니다"
    end

    test "소유자가 아니면 리다이렉트된다", %{conn: conn} do
      other_user = DiscussAuth.AccountsFixtures.user_fixture()
      topic = topic_fixture(%{auth_user_id: other_user.id})
      conn = delete(conn, ~p"/topics/#{topic.id}")
      assert redirected_to(conn) == ~p"/topics"
    end
  end
end
