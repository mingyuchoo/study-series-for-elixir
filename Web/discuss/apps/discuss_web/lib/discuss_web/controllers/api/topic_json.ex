defmodule DiscussWeb.Api.TopicJSON do
  alias Discuss.Topics.Topic

  def index(%{topics: topics, page: page, per_page: per_page, total: total}) do
    %{
      data: Enum.map(topics, &data/1),
      meta: %{
        page: page,
        per_page: per_page,
        total: total,
        total_pages: ceil(total / per_page)
      }
    }
  end

  def show(%{topic: topic}) do
    %{data: data(topic)}
  end

  defp data(%Topic{} = topic) do
    %{
      id: topic.id,
      title: topic.title,
      body: topic.body,
      body_html: Discuss.Markdown.to_html(topic.body),
      auth_user_id: topic.auth_user_id,
      inserted_at: topic.inserted_at,
      updated_at: topic.updated_at
    }
  end
end
