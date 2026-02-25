defmodule Core.Agent.Worker do
  @moduledoc """
  대화 상태와 도구 실행을 처리하는 에이전트 워커.
  ReAct (Reasoning + Acting) 패턴을 구현합니다.
  """
  use GenServer
  require Logger

  alias Core.Agent.{ReactEngine, ToolRegistry}
  alias Core.Schema.{Conversation, Message}
  alias Core.Repo

  defstruct [:conversation_id, :messages, :tools]

  # 클라이언트 API

  def start_link(opts) do
    conversation_id = Keyword.fetch!(opts, :conversation_id)
    GenServer.start_link(__MODULE__, conversation_id, name: via_tuple(conversation_id))
  end

  def chat(conversation_id, user_message) do
    GenServer.call(via_tuple(conversation_id), {:chat, user_message}, 120_000)
  end

  def get_history(conversation_id) do
    GenServer.call(via_tuple(conversation_id), :get_history)
  end

  # 서버 콜백

  @impl true
  def init(conversation_id) do
    state = %__MODULE__{
      conversation_id: conversation_id,
      messages: load_messages(conversation_id),
      tools: ToolRegistry.get_tools()
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:chat, user_message}, _from, state) do
    # 사용자 메시지 추가
    user_msg = %{role: "user", content: user_message, tool_calls: nil, tool_call_id: nil}
    state = add_message(state, user_msg)

    # ReactEngine 실행
    system_prompt = get_system_prompt(state.conversation_id)

    case ReactEngine.run(state.messages, state.tools, system_prompt: system_prompt) do
      {:ok, response, updated_messages} ->
        # 새 메시지(어시스턴트 + 도구 메시지)를 DB에 저장
        new_messages = Enum.drop(updated_messages, length(state.messages))
        state = save_new_messages(state, new_messages)

        {:reply, {:ok, response}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_history, _from, state) do
    {:reply, state.messages, state}
  end

  # 헬퍼 함수들

  defp via_tuple(conversation_id) do
    {:via, Registry, {Core.Agent.Registry, conversation_id}}
  end

  defp load_messages(conversation_id) do
    import Ecto.Query

    Message
    |> where([m], m.conversation_id == ^conversation_id)
    |> order_by([m], asc: m.inserted_at)
    |> Repo.all()
    |> Enum.map(&message_to_map/1)
  end

  defp add_message(state, attrs) do
    # 데이터베이스에 저장
    {:ok, message} =
      %Message{}
      |> Message.changeset(Map.put(attrs, :conversation_id, state.conversation_id))
      |> Repo.insert()

    # 상태 업데이트
    %{state | messages: state.messages ++ [message_to_map(message)]}
  end

  defp save_new_messages(state, new_messages) do
    saved_messages =
      Enum.map(new_messages, fn msg ->
        attrs = Map.put(msg, :conversation_id, state.conversation_id)

        {:ok, message} =
          %Message{}
          |> Message.changeset(attrs)
          |> Repo.insert()

        message_to_map(message)
      end)

    %{state | messages: state.messages ++ saved_messages}
  end

  defp message_to_map(%Message{} = message) do
    %{
      role: to_string(message.role),
      content: message.content,
      tool_calls: message.tool_calls,
      tool_call_id: message.tool_call_id
    }
  end

  defp get_system_prompt(conversation_id) do
    case Repo.get(Conversation, conversation_id) do
      %{system_prompt: prompt} when not is_nil(prompt) -> prompt
      _ -> default_system_prompt()
    end
  end

  defp default_system_prompt do
    """
    당신은 다양한 도구에 접근할 수 있는 유용한 AI 어시스턴트입니다.
    작업을 수행하거나 정보를 얻어야 할 때는 사용 가능한 도구를 활용하세요.
    도구를 사용하기 전에 항상 추론 과정을 설명하세요.
    도구 결과를 받은 후에는 분석하고 유용한 응답을 제공하세요.
    설명은 간결하지만 철저하게 해주세요.
    """
  end
end
