defmodule DiscussWeb.TopicController do
  use DiscussWeb, :controller
  alias Discuss.Topics

  def index(conn, params) do
    page = String.to_integer(params["page"] || "1")
    search = params["search"] || ""
    my_topics = params["my_topics"] == "true"

    opts =
      [page: page, search: search]
      |> then(fn opts ->
        if my_topics, do: Keyword.put(opts, :user_id, conn.assigns.current_user.id), else: opts
      end)

    result = Topics.list_topics(opts)

    render(conn, :index,
      layout: false,
      topics: result.topics,
      page: result.page,
      per_page: result.per_page,
      total: result.total,
      search: search,
      my_topics: my_topics
    )
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
    case authorize_topic(conn, id) do
      {:ok, topic} ->
        changeset = Topics.change_topic(topic)
        render(conn, :edit, layout: false, changeset: changeset, topic: topic)

      conn ->
        conn
    end
  end

  def update(conn, %{"id" => id, "topic" => topic_params}) do
    case authorize_topic(conn, id) do
      {:ok, topic} ->
        case Topics.update_topic(topic, topic_params) do
          {:ok, topic} ->
            conn
            |> put_flash(:info, "\"#{topic.title}\" 토픽이 업데이트되었습니다.")
            |> redirect(to: ~p"/topics")

          {:error, changeset} ->
            render(conn, :edit, layout: false, changeset: changeset, topic: topic)
        end

      conn ->
        conn
    end
  end

  def delete(conn, %{"id" => id}) do
    case authorize_topic(conn, id) do
      {:ok, topic} ->
        {:ok, _topic} = Topics.soft_delete_topic(topic)

        conn
        |> put_flash(:info, "토픽이 삭제되었습니다.")
        |> redirect(to: ~p"/topics")

      conn ->
        conn
    end
  end

  defp authorize_topic(conn, id) do
    user_id = conn.assigns.current_user.id

    case Topics.get_topic_for_user!(id, user_id) do
      topic -> {:ok, topic}
    end
  rescue
    Ecto.NoResultsError ->
      conn
      |> put_flash(:error, "해당 토픽에 접근 권한이 없습니다.")
      |> redirect(to: ~p"/topics")
      |> halt()
  end
end
