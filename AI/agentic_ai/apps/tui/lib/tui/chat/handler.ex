defmodule TUI.Chat.Handler do
  @moduledoc """
  AI 에이전트와의 통신을 처리하는 GenServer.

  SupervisorAgent.stream_chat/3를 호출하고 스트리밍 응답을 수신하여
  Ratatouille 앱에 전달합니다.
  """

  use GenServer
  require Logger

  alias Core.Agent.{Supervisor, SupervisorAgent}
  alias Core.Contexts.{Agents, Conversations}
  alias Core.Agent.MemoryManager

  defstruct [
    :current_conversation_id,
    pending_messages: [],
    streaming: false
  ]

  # ============================================
  # 클라이언트 API
  # ============================================

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %__MODULE__{}, name: __MODULE__)
  end

  @doc """
  메시지를 에이전트에게 전송합니다.
  비동기로 처리되며, 결과는 pending_messages를 통해 전달됩니다.
  """
  def send_message(conversation_id, message) do
    GenServer.cast(__MODULE__, {:send_message, conversation_id, message})
  end

  @doc """
  대기 중인 메시지를 가져옵니다.
  Ratatouille subscribe에서 주기적으로 호출됩니다.
  """
  def get_pending_messages do
    GenServer.call(__MODULE__, :get_pending_messages)
  end

  @doc """
  새 대화를 생성합니다.
  """
  def create_conversation do
    GenServer.call(__MODULE__, :create_conversation)
  end

  @doc """
  대화를 선택합니다.
  """
  def select_conversation(conversation_id) do
    GenServer.call(__MODULE__, {:select_conversation, conversation_id})
  end

  @doc """
  대화 목록을 가져옵니다.
  """
  def list_conversations do
    GenServer.call(__MODULE__, :list_conversations)
  end

  @doc """
  사용자 프로필을 가져옵니다.
  """
  def get_user_profile do
    GenServer.call(__MODULE__, :get_user_profile)
  end

  @doc """
  대화를 삭제합니다.
  """
  def delete_conversation(conversation_id) do
    GenServer.call(__MODULE__, {:delete_conversation, conversation_id})
  end

  # ============================================
  # 서버 콜백
  # ============================================

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_cast({:send_message, conversation_id, message}, state) do
    # 에이전트가 실행 중인지 확인
    ensure_agent_started(conversation_id)

    # 현재 프로세스를 콜백 수신자로 설정하고 스트리밍 시작
    handler_pid = self()

    Task.start(fn ->
      result = SupervisorAgent.stream_chat(conversation_id, message, handler_pid)

      case result do
        {:ok, response} ->
          send(handler_pid, {:stream_complete_internal, response})

        {:error, reason} ->
          send(handler_pid, {:stream_error_internal, reason})
      end
    end)

    {:noreply, %{state | current_conversation_id: conversation_id, streaming: true}}
  end

  @impl true
  def handle_call(:get_pending_messages, _from, state) do
    # 대기 중인 메시지 반환하고 큐 비우기
    {:reply, Enum.reverse(state.pending_messages), %{state | pending_messages: []}}
  end

  @impl true
  def handle_call(:create_conversation, _from, state) do
    timestamp = DateTime.utc_now() |> Calendar.strftime("%Y-%m-%d %H:%M")

    case Conversations.create_conversation(%{title: "New Chat #{timestamp}"}) do
      {:ok, conversation} ->
        # 에이전트 시작
        ensure_agent_started(conversation.id)

        new_state =
          state
          |> queue_message({:conversation_created, conversation})

        {:reply, {:ok, conversation}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:select_conversation, conversation_id}, _from, state) do
    ensure_agent_started(conversation_id)
    messages = Conversations.list_messages(conversation_id)
    conversation = Conversations.get_conversation(conversation_id)

    new_state =
      state
      |> queue_message({:conversation_selected, conversation})
      |> queue_message({:messages_loaded, messages})

    {:reply, {:ok, conversation}, %{new_state | current_conversation_id: conversation_id}}
  end

  @impl true
  def handle_call(:list_conversations, _from, state) do
    conversations = Conversations.list_conversations()
    {:reply, {:ok, conversations}, state}
  end

  @impl true
  def handle_call(:get_user_profile, _from, state) do
    result = MemoryManager.get_user_profile()
    {:reply, result, state}
  end

  @impl true
  def handle_call({:delete_conversation, conversation_id}, _from, state) do
    case Conversations.get_conversation(conversation_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      conversation ->
        case Conversations.delete_conversation(conversation) do
          {:ok, _} ->
            new_state = queue_message(state, {:conversation_deleted, conversation_id})
            {:reply, :ok, new_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  # ============================================
  # 스트리밍 메시지 수신 (SupervisorAgent에서 전송)
  # ============================================

  @impl true
  def handle_info({:stream_chunk, _conv_id, text}, state) do
    {:noreply, queue_message(state, {:stream_chunk, text})}
  end

  @impl true
  def handle_info({:stream_tool_start, _conv_id, tool_names}, state) do
    {:noreply, queue_message(state, {:stream_tool_start, tool_names})}
  end

  @impl true
  def handle_info({:stream_tool_end, _conv_id}, state) do
    {:noreply, queue_message(state, {:stream_tool_end})}
  end

  @impl true
  def handle_info({:stream_postprocess, _conv_id}, state) do
    {:noreply, queue_message(state, {:stream_postprocess})}
  end

  @impl true
  def handle_info({:stream_finish, _conv_id}, state) do
    {:noreply, queue_message(state, {:stream_finish})}
  end

  @impl true
  def handle_info({:stream_complete, _conv_id, response}, state) do
    new_state =
      %{state | streaming: false}
      |> queue_message({:stream_complete, response})

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:stream_complete_internal, response}, state) do
    new_state =
      %{state | streaming: false}
      |> queue_message({:stream_complete, response})

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:stream_error_internal, reason}, state) do
    new_state =
      %{state | streaming: false}
      |> queue_message({:stream_error, reason})

    {:noreply, new_state}
  end

  # 알 수 없는 메시지 무시
  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ============================================
  # 비공개 함수
  # ============================================

  defp ensure_agent_started(conversation_id) do
    case Registry.lookup(Core.Agent.Registry, {:supervisor, conversation_id}) do
      [] ->
        case Agents.get_active_supervisor() do
          nil ->
            Logger.warning("No active supervisor agent found")
            :ok

          supervisor ->
            case Supervisor.start_supervisor_agent(supervisor.id, conversation_id) do
              {:ok, _pid} ->
                Logger.debug("Started supervisor agent for conversation #{conversation_id}")
                :ok

              {:error, {:already_started, _pid}} ->
                :ok

              {:error, reason} ->
                Logger.error("Failed to start supervisor agent: #{inspect(reason)}")
                :ok
            end
        end

      _ ->
        :ok
    end
  end

  defp queue_message(state, message) do
    %{state | pending_messages: [message | state.pending_messages]}
  end
end
