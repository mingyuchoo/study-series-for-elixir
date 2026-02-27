defmodule DiscussWeb.ChangesetJSONTest do
  use DiscussWeb.ConnCase, async: true

  alias Discuss.Topics.Topic

  test "changeset 에러를 JSON으로 변환한다" do
    {:error, changeset} =
      Topic.changeset(%Topic{}, %{})
      |> Ecto.Changeset.apply_action(:insert)

    result = DiscussWeb.ChangesetJSON.error(%{changeset: changeset})
    assert %{errors: errors} = result
    assert errors[:title] == ["can't be blank"]
  end
end
