defmodule DiscussWeb.Api.TopicController do
  use DiscussWeb, :controller

  alias Discuss.Topics

  action_fallback DiscussWeb.FallbackController

  def index(conn, params) do
    page = String.to_integer(params["page"] || "1")
    search = params["search"] || ""

    result = Topics.list_topics(page: page, search: search)

    render(conn, :index,
      topics: result.topics,
      page: result.page,
      per_page: result.per_page,
      total: result.total
    )
  end

  def show(conn, %{"id" => id}) do
    topic = Topics.get_topic!(id)
    render(conn, :show, topic: topic)
  end

  def create(conn, %{"topic" => topic_params}) do
    topic_params = Map.put(topic_params, "auth_user_id", conn.assigns.current_user.id)

    case Topics.create_topic(topic_params) do
      {:ok, topic} ->
        conn
        |> put_status(:created)
        |> put_resp_header("location", ~p"/api/topics/#{topic.id}")
        |> render(:show, topic: topic)

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> put_view(DiscussWeb.ChangesetJSON)
        |> render(:error, changeset: changeset)
    end
  end

  def update(conn, %{"id" => id, "topic" => topic_params}) do
    case Topics.get_topic_for_user!(id, conn.assigns.current_user.id) do
      topic ->
        case Topics.update_topic(topic, topic_params) do
          {:ok, topic} ->
            render(conn, :show, topic: topic)

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> put_view(DiscussWeb.ChangesetJSON)
            |> render(:error, changeset: changeset)
        end
    end
  rescue
    Ecto.NoResultsError ->
      conn
      |> put_status(:forbidden)
      |> json(%{errors: %{detail: "접근 권한이 없습니다."}})
  end

  def delete(conn, %{"id" => id}) do
    case Topics.get_topic_for_user!(id, conn.assigns.current_user.id) do
      topic ->
        {:ok, _} = Topics.soft_delete_topic(topic)
        send_resp(conn, :no_content, "")
    end
  rescue
    Ecto.NoResultsError ->
      conn
      |> put_status(:forbidden)
      |> json(%{errors: %{detail: "접근 권한이 없습니다."}})
  end
end
