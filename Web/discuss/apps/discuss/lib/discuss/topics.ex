defmodule Discuss.Topics do
  @moduledoc """
  토픽 관련 비즈니스 로직을 캡슐화하는 Context 모듈.
  """

  import Ecto.Query, warn: false
  alias Discuss.Repo
  alias Discuss.Topics.Topic

  @per_page 10

  @doc """
  페이지네이션, 검색, 사용자 필터를 적용하여 토픽을 조회한다.
  삭제된 토픽(deleted_at이 설정된 것)은 제외한다.

  ## 옵션
    - `:page` - 페이지 번호 (기본값: 1)
    - `:search` - 제목 검색어 (ILIKE)
    - `:user_id` - 특정 사용자의 토픽만 조회
  """
  def list_topics(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    search = Keyword.get(opts, :search, nil)
    user_id = Keyword.get(opts, :user_id, nil)
    offset = (page - 1) * @per_page

    base_query =
      from t in Topic,
        where: is_nil(t.deleted_at),
        order_by: [desc: t.inserted_at]

    base_query =
      if search && search != "" do
        from t in base_query, where: ilike(t.title, ^"%#{search}%")
      else
        base_query
      end

    base_query =
      if user_id do
        from t in base_query, where: t.auth_user_id == ^user_id
      else
        base_query
      end

    topics = Repo.all(from t in base_query, limit: @per_page, offset: ^offset)
    total = Repo.aggregate(base_query, :count, :id)

    %{topics: topics, page: page, per_page: @per_page, total: total}
  end

  def get_topic!(id) do
    Repo.get!(Topic, id)
  end

  @doc """
  소유자 검증이 포함된 토픽 조회. 소유자가 아니면 Ecto.NoResultsError를 발생시킨다.
  """
  def get_topic_for_user!(id, user_id) do
    case Repo.get!(Topic, id) do
      %Topic{auth_user_id: ^user_id} = topic -> topic
      _ -> raise Ecto.NoResultsError, queryable: Topic
    end
  end

  def create_topic(attrs \\ %{}) do
    %Topic{}
    |> Topic.changeset(attrs)
    |> Repo.insert()
  end

  def update_topic(%Topic{} = topic, attrs) do
    topic
    |> Topic.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  소프트 삭제: deleted_at에 현재 시간을 설정한다.
  """
  def soft_delete_topic(%Topic{} = topic) do
    topic
    |> Ecto.Changeset.change(deleted_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.update()
  end

  @doc """
  하드 삭제: DB에서 완전히 제거한다 (관리자용).
  """
  def delete_topic(%Topic{} = topic) do
    Repo.delete(topic)
  end

  def change_topic(%Topic{} = topic, attrs \\ %{}) do
    Topic.changeset(topic, attrs)
  end
end
