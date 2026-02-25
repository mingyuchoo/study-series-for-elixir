defmodule Core.Contexts.Conversations do
  @moduledoc """
  대화(Conversation) 관련 컨텍스트 함수들.

  대화 생성, 조회, 삭제 및 메시지 관리 기능을 제공합니다.
  """

  import Ecto.Query
  alias Core.Repo
  alias Core.Schema.{Conversation, Message}

  @doc """
  모든 대화 목록을 반환합니다.
  최신 순으로 정렬됩니다.
  """
  def list_conversations do
    from(c in Conversation,
      where: c.status == :active,
      order_by: [desc: c.updated_at]
    )
    |> Repo.all()
  end

  @doc """
  특정 대화를 ID로 조회합니다.
  """
  def get_conversation(id) do
    Repo.get(Conversation, id)
  end

  @doc """
  대화를 ID로 조회하고, 없으면 에러를 발생시킵니다.
  """
  def get_conversation!(id) do
    Repo.get!(Conversation, id)
  end

  @doc """
  새 대화를 생성합니다.

  ## Examples

      iex> create_conversation(%{title: "New Chat"})
      {:ok, %Conversation{}}

      iex> create_conversation(%{})
      {:error, %Ecto.Changeset{}}
  """
  def create_conversation(attrs \\ %{}) do
    %Conversation{}
    |> Conversation.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  대화를 업데이트합니다.
  """
  def update_conversation(%Conversation{} = conversation, attrs) do
    conversation
    |> Conversation.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  대화를 삭제합니다.
  """
  def delete_conversation(%Conversation{} = conversation) do
    Repo.delete(conversation)
  end

  @doc """
  대화를 보관(archive)합니다.
  """
  def archive_conversation(%Conversation{} = conversation) do
    update_conversation(conversation, %{status: :archived})
  end

  @doc """
  특정 대화의 메시지 목록을 반환합니다.
  시간 순으로 정렬됩니다.
  """
  def list_messages(conversation_id) do
    from(m in Message,
      where: m.conversation_id == ^conversation_id,
      order_by: [asc: m.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  특정 대화의 최근 메시지를 반환합니다.
  """
  def list_recent_messages(conversation_id, limit \\ 10) do
    from(m in Message,
      where: m.conversation_id == ^conversation_id,
      order_by: [desc: m.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
    |> Enum.reverse()
  end

  @doc """
  대화에 메시지를 추가합니다.
  """
  def create_message(attrs) do
    %Message{}
    |> Message.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  대화의 메시지 수를 반환합니다.
  """
  def count_messages(conversation_id) do
    from(m in Message,
      where: m.conversation_id == ^conversation_id,
      select: count(m.id)
    )
    |> Repo.one()
  end
end
