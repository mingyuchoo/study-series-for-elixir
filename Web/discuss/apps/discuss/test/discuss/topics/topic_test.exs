defmodule Discuss.Topics.TopicTest do
  use Discuss.DataCase

  alias Discuss.Topics.Topic

  describe "changeset/2" do
    test "유효한 속성으로 유효한 changeset을 반환한다" do
      changeset = Topic.changeset(%Topic{}, %{title: "유효한 제목", auth_user_id: 1})
      assert changeset.valid?
    end

    test "제목이 없으면 에러를 반환한다" do
      changeset = Topic.changeset(%Topic{}, %{auth_user_id: 1})
      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end

    test "제목이 2자 미만이면 에러를 반환한다" do
      changeset = Topic.changeset(%Topic{}, %{title: "a", auth_user_id: 1})
      assert %{title: [msg]} = errors_on(changeset)
      assert msg =~ "at least"
    end

    test "제목이 100자를 초과하면 에러를 반환한다" do
      long_title = String.duplicate("가", 101)
      changeset = Topic.changeset(%Topic{}, %{title: long_title, auth_user_id: 1})
      assert %{title: [msg]} = errors_on(changeset)
      assert msg =~ "at most"
    end

    test "제목이 정확히 2자이면 유효하다" do
      changeset = Topic.changeset(%Topic{}, %{title: "ab", auth_user_id: 1})
      assert changeset.valid?
    end

    test "제목이 정확히 100자이면 유효하다" do
      title = String.duplicate("가", 100)
      changeset = Topic.changeset(%Topic{}, %{title: title, auth_user_id: 1})
      assert changeset.valid?
    end

    test "auth_user_id 없이도 changeset은 유효하다" do
      changeset = Topic.changeset(%Topic{}, %{title: "제목만 있는 토픽"})
      assert changeset.valid?
    end
  end
end
