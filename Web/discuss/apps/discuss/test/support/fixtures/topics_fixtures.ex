defmodule Discuss.TopicsFixtures do
  @moduledoc """
  Topics 컨텍스트용 테스트 픽스처.
  """

  def valid_topic_attributes(attrs \\ %{}) do
    # atom 키와 string 키를 모두 지원하기 위해 정규화
    auth_user_id = attrs["auth_user_id"] || attrs[:auth_user_id]
    title = attrs["title"] || attrs[:title] || "테스트 토픽 #{System.unique_integer([:positive])}"
    body = attrs["body"] || attrs[:body]

    result = %{"title" => title, "auth_user_id" => auth_user_id}
    if body, do: Map.put(result, "body", body), else: result
  end

  def topic_fixture(attrs \\ %{}) do
    {:ok, topic} =
      attrs
      |> valid_topic_attributes()
      |> Discuss.Topics.create_topic()

    topic
  end
end
