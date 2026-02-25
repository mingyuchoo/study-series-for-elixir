defmodule DiscussWeb.TopicController do
  use DiscussWeb, :controller
  alias Discuss.Topics

  def index(conn, _params) do
    topics = Topics.list_topics()

    render(conn, :index, layout: false, topics: topics)
  end

  def new(conn, _params) do
    changeset = Topics.change_topic(%Topics.Topic{})
    render(conn, :new, layout: false, changeset: changeset)
  end

  def create(conn, %{"topic" => topic_params}) do
    topic_params = Map.put(topic_params, "auth_user_id", conn.assigns.current_user.id)

    case Topics.create_topic(topic_params) do
      {:ok, topic} ->
        conn
        |> put_flash(:info, "\"#{topic.title}\" 토픽이 생성되었습니다.")
        |> redirect(to: ~p"/topics")

      {:error, changeset} ->
        render(conn, :new, layout: false, changeset: changeset)
    end
  end

  def show(conn, %{"id" => id}) do
    topic = Topics.get_topic!(id)
    render(conn, :show, layout: false, topic: topic)
  end

  def edit(conn, %{"id" => id}) do
    topic = Topics.get_topic!(id)
    changeset = Topics.change_topic(topic)
    render(conn, :edit, layout: false, changeset: changeset, topic: topic)
  end

  def update(conn, %{"id" => id, "topic" => topic_params}) do
    topic = Topics.get_topic!(id)

    case Topics.update_topic(topic, topic_params) do
      {:ok, topic} ->
        conn
        |> put_flash(:info, "\"#{topic.title}\" 토픽이 업데이트되었습니다.")
        |> redirect(to: ~p"/topics")

      {:error, changeset} ->
        render(conn, :edit, layout: false, changeset: changeset, topic: topic)
    end
  end

  def delete(conn, %{"id" => id}) do
    topic = Topics.get_topic!(id)
    {:ok, _topic} = Topics.delete_topic(topic)

    conn
    |> put_flash(:info, "토픽이 삭제되었습니다.")
    |> redirect(to: ~p"/topics")
  end
end
