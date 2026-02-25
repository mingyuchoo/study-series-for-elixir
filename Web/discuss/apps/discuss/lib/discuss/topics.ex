defmodule Discuss.Topics do
  @moduledoc """
  토픽 관련 비즈니스 로직을 캡슐화하는 Context 모듈.
  """

  import Ecto.Query, warn: false
  alias Discuss.Repo
  alias Discuss.Topics.Topic

  def list_topics do
    Repo.all(Topic)
  end

  def get_topic!(id) do
    Repo.get!(Topic, id)
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

  def delete_topic(%Topic{} = topic) do
    Repo.delete(topic)
  end

  def change_topic(%Topic{} = topic, attrs \\ %{}) do
    Topic.changeset(topic, attrs)
  end
end
