defmodule Discuss.TopicsTest do
  use Discuss.DataCase

  alias Discuss.Topics
  alias Discuss.Topics.Topic

  import Discuss.TopicsFixtures

  defp create_auth_user(_context \\ %{}) do
    {:ok, user} =
      DiscussAuth.Accounts.register_user(%{
        email: "user#{System.unique_integer([:positive])}@example.com",
        password: "hello_world!"
      })

    %{user: user}
  end

  describe "list_topics/1" do
    test "삭제되지 않은 모든 토픽을 반환한다" do
      %{user: user} = create_auth_user()
      topic = topic_fixture(%{auth_user_id: user.id})

      result = Topics.list_topics()
      assert Enum.any?(result.topics, &(&1.id == topic.id))
    end

    test "삭제된 토픽은 반환하지 않는다" do
      %{user: user} = create_auth_user()
      topic = topic_fixture(%{auth_user_id: user.id})
      Topics.soft_delete_topic(topic)

      result = Topics.list_topics()
      refute Enum.any?(result.topics, &(&1.id == topic.id))
    end

    test "검색어로 토픽을 필터링한다" do
      %{user: user} = create_auth_user()
      topic_fixture(%{auth_user_id: user.id, title: "엘릭서 학습"})
      topic_fixture(%{auth_user_id: user.id, title: "피닉스 프레임워크"})

      result = Topics.list_topics(search: "엘릭서")
      assert length(result.topics) == 1
      assert hd(result.topics).title == "엘릭서 학습"
    end

    test "빈 검색어는 필터링하지 않는다" do
      %{user: user} = create_auth_user()
      topic_fixture(%{auth_user_id: user.id})

      result = Topics.list_topics(search: "")
      assert length(result.topics) >= 1
    end

    test "nil 검색어는 필터링하지 않는다" do
      %{user: user} = create_auth_user()
      topic_fixture(%{auth_user_id: user.id})

      result = Topics.list_topics(search: nil)
      assert length(result.topics) >= 1
    end

    test "사용자 ID로 토픽을 필터링한다" do
      %{user: user1} = create_auth_user()
      %{user: user2} = create_auth_user()
      topic_fixture(%{auth_user_id: user1.id, title: "사용자1 토픽"})
      topic_fixture(%{auth_user_id: user2.id, title: "사용자2 토픽"})

      result = Topics.list_topics(user_id: user1.id)
      assert Enum.all?(result.topics, &(&1.auth_user_id == user1.id))
    end

    test "user_id가 nil이면 필터링하지 않는다" do
      %{user: user} = create_auth_user()
      topic_fixture(%{auth_user_id: user.id})

      result = Topics.list_topics(user_id: nil)
      assert length(result.topics) >= 1
    end

    test "페이지네이션이 올바르게 동작한다" do
      %{user: user} = create_auth_user()

      for i <- 1..12 do
        topic_fixture(%{auth_user_id: user.id, title: "토픽 #{i}"})
      end

      result = Topics.list_topics(page: 1)
      assert length(result.topics) == 10
      assert result.per_page == 10
      assert result.total >= 12

      result2 = Topics.list_topics(page: 2)
      assert length(result2.topics) >= 2
    end

    test "메타 정보를 올바르게 반환한다" do
      %{user: user} = create_auth_user()
      topic_fixture(%{auth_user_id: user.id})

      result = Topics.list_topics()
      assert is_integer(result.page)
      assert is_integer(result.per_page)
      assert is_integer(result.total)
    end
  end

  describe "get_topic!/1" do
    test "존재하는 토픽을 반환한다" do
      %{user: user} = create_auth_user()
      topic = topic_fixture(%{auth_user_id: user.id})

      fetched = Topics.get_topic!(topic.id)
      assert fetched.id == topic.id
      assert fetched.title == topic.title
    end

    test "존재하지 않는 ID로 조회하면 에러를 발생시킨다" do
      assert_raise Ecto.NoResultsError, fn ->
        Topics.get_topic!(0)
      end
    end
  end

  describe "get_topic_for_user!/2" do
    test "소유자가 맞으면 토픽을 반환한다" do
      %{user: user} = create_auth_user()
      topic = topic_fixture(%{auth_user_id: user.id})

      fetched = Topics.get_topic_for_user!(topic.id, user.id)
      assert fetched.id == topic.id
    end

    test "소유자가 아니면 에러를 발생시킨다" do
      %{user: user} = create_auth_user()
      %{user: other_user} = create_auth_user()
      topic = topic_fixture(%{auth_user_id: user.id})

      assert_raise Ecto.NoResultsError, fn ->
        Topics.get_topic_for_user!(topic.id, other_user.id)
      end
    end

    test "존재하지 않는 토픽이면 에러를 발생시킨다" do
      assert_raise Ecto.NoResultsError, fn ->
        Topics.get_topic_for_user!(0, 1)
      end
    end
  end

  describe "create_topic/1" do
    test "유효한 데이터로 토픽을 생성한다" do
      %{user: user} = create_auth_user()

      assert {:ok, %Topic{} = topic} =
               Topics.create_topic(%{"title" => "새 토픽", "auth_user_id" => user.id})

      assert topic.title == "새 토픽"
      assert topic.auth_user_id == user.id
    end

    test "제목이 없으면 에러를 반환한다" do
      assert {:error, changeset} = Topics.create_topic(%{"title" => ""})
      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end

    test "제목이 너무 짧으면 에러를 반환한다" do
      assert {:error, changeset} = Topics.create_topic(%{"title" => "a"})
      assert %{title: [_]} = errors_on(changeset)
    end

    test "기본 인자로 호출하면 빈 맵을 사용한다" do
      assert {:error, changeset} = Topics.create_topic()
      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "update_topic/2" do
    test "유효한 데이터로 토픽을 업데이트한다" do
      %{user: user} = create_auth_user()
      topic = topic_fixture(%{auth_user_id: user.id})

      assert {:ok, updated} = Topics.update_topic(topic, %{title: "수정된 제목"})
      assert updated.title == "수정된 제목"
    end

    test "유효하지 않은 데이터로 업데이트하면 에러를 반환한다" do
      %{user: user} = create_auth_user()
      topic = topic_fixture(%{auth_user_id: user.id})

      assert {:error, changeset} = Topics.update_topic(topic, %{title: ""})
      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "soft_delete_topic/1" do
    test "deleted_at에 현재 시간을 설정한다" do
      %{user: user} = create_auth_user()
      topic = topic_fixture(%{auth_user_id: user.id})

      assert is_nil(topic.deleted_at)
      assert {:ok, deleted} = Topics.soft_delete_topic(topic)
      refute is_nil(deleted.deleted_at)
    end
  end

  describe "delete_topic/1" do
    test "토픽을 DB에서 완전히 삭제한다" do
      %{user: user} = create_auth_user()
      topic = topic_fixture(%{auth_user_id: user.id})

      assert {:ok, _} = Topics.delete_topic(topic)

      assert_raise Ecto.NoResultsError, fn ->
        Topics.get_topic!(topic.id)
      end
    end
  end

  describe "change_topic/2" do
    test "changeset을 반환한다" do
      %{user: user} = create_auth_user()
      topic = topic_fixture(%{auth_user_id: user.id})

      changeset = Topics.change_topic(topic)
      assert %Ecto.Changeset{} = changeset
    end

    test "속성과 함께 changeset을 반환한다" do
      changeset = Topics.change_topic(%Topic{}, %{title: "새 제목"})
      assert %Ecto.Changeset{} = changeset
      assert Ecto.Changeset.get_change(changeset, :title) == "새 제목"
    end
  end
end
