defmodule WebWeb.ChatLive do
  use WebWeb, :live_view

  alias Core.Schema.{Conversation, Message}
  alias Core.Repo
  alias Core.Agent.{MemoryManager, Supervisor, SupervisorAgent}
  alias Core.Contexts.{Agents, Mcps}

  import Ecto.Query

  # Markdown 렌더링 옵션
  @earmark_options %Earmark.Options{
    code_class_prefix: "language-",
    smartypants: false,
    breaks: true
  }

  @impl true
  def mount(_params, _session, socket) do
    conversations = list_conversations()
    available_agents = Agents.list_agents(status: :active)
    available_mcps = Mcps.list_mcps_with_status()

    # 사용자 프로필 확인 (표시용)
    user_profile = get_user_profile_for_display()

    socket =
      socket
      |> assign(:conversations, conversations)
      |> assign(:current_conversation, nil)
      |> assign(:messages, [])
      |> assign(:input, "")
      |> assign(:loading, false)
      |> assign(:available_agents, available_agents)
      |> assign(:available_mcps, available_mcps)
      |> assign(:agent_usage_history, [])
      |> assign(:user_profile, user_profile)
      |> assign(:message_sent_at, nil)
      |> assign(:streaming_content, "")
      |> assign(:streaming_message_id, nil)
      |> assign(:streaming_status, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    conversation = Repo.get!(Conversation, id)
    messages = list_messages(id)

    # 실행 중이 아니면 에이전트 시작
    ensure_agent_started(id)

    # 대화 선택 시 이력 초기화 (새 질문 시에만 표시)
    socket =
      socket
      |> assign(:current_conversation, conversation)
      |> assign(:messages, messages)
      |> assign(:agent_usage_history, [])
      |> assign(:message_sent_at, nil)

    {:noreply, socket}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("new_conversation", _params, socket) do
    {:ok, conversation} =
      %Conversation{}
      |> Conversation.changeset(%{
        title: "New Chat #{DateTime.utc_now() |> DateTime.to_string()}"
      })
      |> Repo.insert()

    socket =
      socket
      |> assign(:conversations, list_conversations())
      |> push_navigate(to: ~p"/chat/#{conversation.id}")

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_conversation", %{"id" => id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/chat/#{id}")}
  end

  @impl true
  def handle_event("delete_conversation", %{"id" => id}, socket) do
    conversation = Repo.get!(Conversation, id)

    # 실행 중인 에이전트 종료
    case Registry.lookup(Core.Agent.Registry, {:supervisor, id}) do
      [{pid, _}] -> Supervisor.stop_agent(pid)
      _ -> :ok
    end

    # 관련 메시지 먼저 삭제
    Message
    |> where([m], m.conversation_id == ^id)
    |> Repo.delete_all()

    # 대화 삭제
    Repo.delete!(conversation)

    # 현재 보고 있던 대화를 삭제한 경우 목록으로 이동
    socket =
      if socket.assigns.current_conversation && socket.assigns.current_conversation.id == id do
        socket
        |> assign(:conversations, list_conversations())
        |> assign(:current_conversation, nil)
        |> assign(:messages, [])
        |> push_navigate(to: ~p"/chat")
      else
        assign(socket, :conversations, list_conversations())
      end

    {:noreply, put_flash(socket, :info, "대화가 삭제되었습니다.")}
  end

  @impl true
  def handle_event("update_input", %{"message" => value}, socket) do
    {:noreply, assign(socket, :input, value)}
  end

  @impl true
  def handle_event("send_message", _params, socket) do
    input = String.trim(socket.assigns.input)

    if input != "" and socket.assigns.current_conversation do
      conversation_id = socket.assigns.current_conversation.id
      now = DateTime.utc_now()
      streaming_message_id = Ecto.UUID.generate()

      # UI 즉시 업데이트
      user_message = %{
        id: Ecto.UUID.generate(),
        role: :user,
        content: input,
        inserted_at: now
      }

      socket =
        socket
        |> assign(:messages, socket.assigns.messages ++ [user_message])
        |> assign(:input, "")
        |> assign(:loading, true)
        |> assign(:message_sent_at, now)
        |> assign(:agent_usage_history, [])
        |> assign(:streaming_content, "")
        |> assign(:streaming_message_id, streaming_message_id)
        |> assign(:streaming_status, :streaming)

      # 에이전트에게 스트리밍 모드로 비동기 전송
      send(self(), {:process_message_stream, conversation_id, input})

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:process_message, conversation_id, input}, socket) do
    case SupervisorAgent.chat(conversation_id, input) do
      {:ok, response} ->
        assistant_message = %{
          id: Ecto.UUID.generate(),
          role: :assistant,
          content: response,
          inserted_at: DateTime.utc_now()
        }

        # 이번 질문에 대한 에이전트 사용 이력만 조회
        message_sent_at = socket.assigns.message_sent_at
        agent_usage_history = Agents.list_agent_usage_history(conversation_id, message_sent_at)

        # 프로필이 업데이트되었을 수 있으므로 새로고침
        user_profile = get_user_profile_for_display()

        socket =
          socket
          |> assign(:messages, socket.assigns.messages ++ [assistant_message])
          |> assign(:loading, false)
          |> assign(:agent_usage_history, agent_usage_history)
          |> assign(:user_profile, user_profile)

        {:noreply, socket}

      {:error, reason} ->
        socket =
          socket
          |> assign(:loading, false)
          |> assign(:agent_usage_history, [])
          |> put_flash(:error, "Error: #{inspect(reason)}")

        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:process_message_stream, conversation_id, input}, socket) do
    # 스트리밍 모드로 에이전트에게 전송
    liveview_pid = self()

    # 별도 프로세스에서 스트리밍 호출 (비동기)
    Task.start(fn ->
      case SupervisorAgent.stream_chat(conversation_id, input, liveview_pid) do
        {:ok, _response} ->
          # 완료 알림 (이미 stream_finish에서 처리됨)
          :ok

        {:error, reason} ->
          send(liveview_pid, {:stream_error, conversation_id, reason})
      end
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:stream_chunk, conversation_id, text}, socket) do
    if socket.assigns.current_conversation &&
         socket.assigns.current_conversation.id == conversation_id do
      # 스트리밍 콘텐츠에 텍스트 추가
      new_content = socket.assigns.streaming_content <> text

      socket =
        socket
        |> assign(:streaming_content, new_content)
        |> assign(:streaming_status, :streaming)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:stream_tool_start, conversation_id, tool_names}, socket) do
    if socket.assigns.current_conversation &&
         socket.assigns.current_conversation.id == conversation_id do
      # 도구 실행 중 상태 표시
      socket =
        socket
        |> assign(:streaming_status, {:tool_executing, tool_names})

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:stream_tool_end, conversation_id}, socket) do
    if socket.assigns.current_conversation &&
         socket.assigns.current_conversation.id == conversation_id do
      # 도구 실행 완료
      socket =
        socket
        |> assign(:streaming_status, :streaming)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:stream_postprocess, conversation_id}, socket) do
    if socket.assigns.current_conversation &&
         socket.assigns.current_conversation.id == conversation_id do
      # 후처리 중 상태
      socket =
        socket
        |> assign(:streaming_status, :postprocessing)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:stream_finish, conversation_id}, socket) do
    if socket.assigns.current_conversation &&
         socket.assigns.current_conversation.id == conversation_id do
      # 스트리밍 완료 - 후처리 결과를 기다림
      # 최종 결과는 stream_complete에서 처리
      socket =
        socket
        |> assign(:streaming_status, :finishing)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:stream_error, conversation_id, reason}, socket) do
    if socket.assigns.current_conversation &&
         socket.assigns.current_conversation.id == conversation_id do
      socket =
        socket
        |> assign(:loading, false)
        |> assign(:streaming_content, "")
        |> assign(:streaming_message_id, nil)
        |> assign(:streaming_status, nil)
        |> assign(:agent_usage_history, [])
        |> put_flash(:error, "스트리밍 오류: #{inspect(reason)}")

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  # 스트리밍 완료 후 최종 메시지 추가 (SupervisorAgent에서 DB 저장 후)
  @impl true
  def handle_info({:stream_complete, conversation_id, final_response}, socket) do
    if socket.assigns.current_conversation &&
         socket.assigns.current_conversation.id == conversation_id do
      assistant_message = %{
        id: socket.assigns.streaming_message_id,
        role: :assistant,
        content: final_response,
        inserted_at: DateTime.utc_now()
      }

      # 에이전트 사용 이력 조회
      message_sent_at = socket.assigns.message_sent_at
      agent_usage_history = Agents.list_agent_usage_history(conversation_id, message_sent_at)

      # 프로필 새로고침
      user_profile = get_user_profile_for_display()

      socket =
        socket
        |> assign(:messages, socket.assigns.messages ++ [assistant_message])
        |> assign(:loading, false)
        |> assign(:streaming_content, "")
        |> assign(:streaming_message_id, nil)
        |> assign(:streaming_status, nil)
        |> assign(:agent_usage_history, agent_usage_history)
        |> assign(:user_profile, user_profile)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  # 비공개 함수들

  defp list_conversations do
    Conversation
    |> order_by([c], desc: c.inserted_at)
    |> limit(20)
    |> Repo.all()
  end

  defp list_messages(conversation_id) do
    Message
    |> where([m], m.conversation_id == ^conversation_id)
    |> order_by([m], asc: m.inserted_at)
    |> Repo.all()
  end

  defp ensure_agent_started(conversation_id) do
    case Registry.lookup(Core.Agent.Registry, {:supervisor, conversation_id}) do
      [] ->
        # 활성화된 supervisor 에이전트 가져오기
        case Agents.get_active_supervisor() do
          nil ->
            # 폴백: supervisor가 설정되지 않음
            :ok

          supervisor ->
            Supervisor.start_supervisor_agent(supervisor.id, conversation_id)
        end

      _ ->
        :ok
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-screen bg-base-100">
      <!-- Sidebar -->
      <div class="w-64 bg-base-200 text-base-content flex flex-col border-r border-base-300">
        <!-- 사용자 프로필 섹션 -->
        <%= if @user_profile do %>
          <div class="p-4 border-b border-base-300 bg-neutral text-neutral-content">
            <div class="flex items-center gap-3">
              <div class="avatar placeholder">
                <div class="w-10 rounded-full bg-neutral-content/20">
                  <span class="text-lg font-bold">
                    {String.first(@user_profile[:user_name] || @user_profile["user_name"] || "?")}
                  </span>
                </div>
              </div>
              <div>
                <div class="font-medium text-sm">
                  {@user_profile[:user_name] || @user_profile["user_name"]}
                </div>
                <div class="text-xs opacity-80 flex items-center gap-1">
                  <.icon name="hero-map-pin" class="w-3 h-3" />
                  {@user_profile[:city] || @user_profile["city"]}
                </div>
              </div>
            </div>
            <div class="mt-2 text-xs opacity-90">
              AI 비서: {@user_profile[:agent_name] || @user_profile["agent_name"]}
            </div>
          </div>
        <% end %>

        <div class="p-4 border-b border-base-300">
          <button phx-click="new_conversation" class="btn btn-primary btn-block gap-2">
            <.icon name="hero-plus" class="w-4 h-4" /> New Chat
          </button>
        </div>

        <ul class="menu menu-sm flex-1 overflow-y-auto p-2 gap-1">
          <%= for conv <- @conversations do %>
            <li>
              <div class={[
                "group flex items-center justify-between",
                @current_conversation && @current_conversation.id == conv.id && "active"
              ]}>
                <div
                  phx-click="select_conversation"
                  phx-value-id={conv.id}
                  class="flex-1 min-w-0"
                >
                  <div class="truncate text-sm font-medium">{conv.title}</div>
                  <div class="text-xs opacity-50">
                    {Calendar.strftime(conv.inserted_at, "%Y-%m-%d %H:%M")}
                  </div>
                </div>
                <button
                  phx-click="delete_conversation"
                  phx-value-id={conv.id}
                  data-confirm="이 대화를 삭제하시겠습니까? 모든 메시지가 함께 삭제됩니다."
                  class="btn btn-ghost btn-xs btn-circle text-error opacity-0 group-hover:opacity-100 transition-opacity"
                  title="대화 삭제"
                >
                  <.icon name="hero-trash" class="w-4 h-4" />
                </button>
              </div>
            </li>
          <% end %>
        </ul>
        
    <!-- MCP Panel -->
        <ul class="menu menu-xs border-t border-base-300 p-2">
          <li class="menu-title">사용 가능한 MCP</li>
          <%= if @available_mcps == [] do %>
            <li class="disabled">
              <span class="text-xs italic opacity-40">설정된 MCP가 없습니다</span>
            </li>
          <% else %>
            <%= for mcp <- @available_mcps do %>
              <li>
                <div class="flex items-center gap-2">
                  <div class="badge badge-secondary badge-sm">
                    <.icon name="hero-server" class="w-3 h-3" />
                  </div>
                  <div class="flex-1 min-w-0">
                    <div class="truncate font-medium text-secondary">
                      {mcp.name}
                    </div>
                    <div class="truncate text-xs opacity-50">
                      {mcp.command} {Enum.join(mcp.args, " ")}
                    </div>
                  </div>
                  <span
                    class={mcp_status_indicator_class(mcp.status)}
                    title={mcp_status_label(mcp.status)}
                  >
                    <span class={mcp_status_dot_class(mcp.status)}></span>
                  </span>
                </div>
              </li>
            <% end %>
          <% end %>
        </ul>
        
    <!-- Agent Panel -->
        <ul class="menu menu-xs border-t border-base-300 p-2">
          <li class="menu-title">사용 가능한 에이전트</li>
          <%= for agent <- @available_agents do %>
            <% usage_info = find_agent_usage(@agent_usage_history, agent.id) %>
            <li>
              <div class={[
                "flex items-center gap-2",
                usage_info && "active"
              ]}>
                <%= if usage_info do %>
                  <div class="badge badge-primary badge-sm font-bold">
                    {usage_info.order}
                  </div>
                <% else %>
                  <div class="badge badge-ghost badge-sm">-</div>
                <% end %>
                <div class="flex-1 min-w-0">
                  <div class="truncate font-medium">
                    {agent.display_name || agent.name}
                  </div>
                  <%= if agent.description do %>
                    <div class="truncate text-xs opacity-50">
                      {agent.description}
                    </div>
                  <% end %>
                </div>
                <%= if usage_info do %>
                  <.icon name="hero-check-circle" class="w-4 h-4 text-success" />
                <% end %>
              </div>
            </li>
          <% end %>
        </ul>

        <%= if @agent_usage_history != [] do %>
          <div class="border-t border-base-300 p-2">
            <div class="text-xs font-semibold opacity-50 uppercase tracking-wider mb-2">
              실행 순서
            </div>
            <div class="flex flex-wrap gap-1">
              <%= for usage <- @agent_usage_history do %>
                <div
                  class="badge badge-primary badge-sm gap-1"
                  title={Calendar.strftime(usage.timestamp, "%H:%M:%S")}
                >
                  <span class="font-bold">{usage.order}.</span>
                  {usage.agent.display_name || usage.agent.name}
                </div>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
      
    <!-- Main Chat Area -->
      <div class="flex-1 flex flex-col">
        <!-- Header -->
        <div class="navbar bg-base-100 border-b border-base-300 shadow-sm px-4">
          <div class="flex-1">
            <div>
              <h1 class="text-xl font-semibold">
                {if @current_conversation,
                  do: @current_conversation.title,
                  else: "Agentic AI Assistant"}
              </h1>
              <p class="text-sm text-base-content/50">Powered by Azure OpenAI gpt-5-mini</p>
            </div>
          </div>
          <div class="flex-none">
            <%= if @current_conversation do %>
              <button
                phx-click="delete_conversation"
                phx-value-id={@current_conversation.id}
                data-confirm="이 대화를 삭제하시겠습니까? 모든 메시지가 함께 삭제됩니다."
                class="btn btn-ghost btn-sm text-error gap-2"
                title="대화 삭제"
              >
                <.icon name="hero-trash" class="w-4 h-4" /> 삭제
              </button>
            <% end %>
          </div>
        </div>
        
    <!-- Messages -->
        <div class="flex-1 overflow-y-auto p-4 space-y-2" id="messages">
          <%= if @messages == [] and @current_conversation do %>
            <div class="hero min-h-[50vh]">
              <div class="hero-content text-center">
                <div class="max-w-md">
                  <h2 class="text-2xl font-bold">대화를 시작하세요!</h2>
                  <p class="py-4 text-base-content/60">
                    AI 어시스턴트가 다양한 도구를 활용하여 도움을 드릴 수 있습니다.
                  </p>
                </div>
              </div>
            </div>
          <% end %>

          <%= for message <- @messages do %>
            <div class={[
              "chat",
              (message.role in [:user, "user"] && "chat-end") || "chat-start"
            ]}>
              <div class="chat-header text-xs opacity-60 mb-1">
                {role_label(message.role)}
              </div>
              <div class={["chat-bubble", chat_bubble_class(message.role)]}>
                <%= if message.role in [:assistant, "assistant"] do %>
                  <div class="prose prose-sm max-w-none">
                    {render_markdown(message.content)}
                  </div>
                <% else %>
                  <div class="whitespace-pre-wrap">{message.content}</div>
                <% end %>
              </div>
            </div>
          <% end %>

          <%= if @loading do %>
            <%= if @streaming_content != "" or @streaming_status do %>
              <!-- 스트리밍 메시지 표시 -->
              <div class="chat chat-start">
                <div class="chat-header text-xs opacity-60 mb-1 flex items-center gap-2">
                  Assistant
                  <%= case @streaming_status do %>
                    <% :streaming -> %>
                      <span class="badge badge-info badge-sm gap-1">
                        <span class="loading loading-dots loading-xs"></span> 실시간 응답 중
                      </span>
                    <% {:tool_executing, tool_names} -> %>
                      <span class="badge badge-warning badge-sm gap-1">
                        <span class="loading loading-spinner loading-xs"></span>
                        {Enum.join(tool_names, ", ")}
                      </span>
                    <% :postprocessing -> %>
                      <span class="badge badge-secondary badge-sm gap-1">
                        <.icon name="hero-sparkles" class="w-3 h-3 animate-pulse" /> 응답 다듬는 중
                      </span>
                    <% :finishing -> %>
                      <span class="badge badge-success badge-sm gap-1">
                        <.icon name="hero-check-circle" class="w-3 h-3" /> 완료 중
                      </span>
                    <% _ -> %>
                      <span class="badge badge-ghost badge-sm">처리 중</span>
                  <% end %>
                </div>
                <div class="chat-bubble chat-bubble-accent">
                  <%= if @streaming_content != "" do %>
                    <div class="prose prose-sm max-w-none">
                      {render_markdown(@streaming_content)}
                    </div>
                    <span class="inline-block w-2 h-4 bg-primary animate-pulse ml-1"></span>
                  <% else %>
                    <span class="loading loading-dots loading-md"></span>
                  <% end %>
                </div>
              </div>
            <% else %>
              <!-- 기존 로딩 표시 -->
              <div class="chat chat-start">
                <div class="chat-bubble chat-bubble-accent">
                  <span class="loading loading-dots loading-md"></span>
                </div>
              </div>
            <% end %>
          <% end %>
        </div>
        
    <!-- Input -->
        <%= if @current_conversation do %>
          <div class="bg-base-100 border-t border-base-300 p-4">
            <form phx-submit="send_message" phx-change="update_input" class="join w-full">
              <input
                type="text"
                name="message"
                value={@input}
                placeholder="메시지를 입력하세요..."
                disabled={@loading}
                class="input input-bordered join-item flex-1"
                autocomplete="off"
              />
              <button
                type="submit"
                disabled={@loading or @input == ""}
                class="btn btn-primary join-item gap-2"
              >
                <.icon name="hero-paper-airplane" class="w-5 h-5" /> Send
              </button>
            </form>
          </div>
        <% else %>
          <div class="bg-base-100 border-t border-base-300 p-4">
            <div class="alert alert-info">
              <.icon name="hero-information-circle" class="w-5 h-5" />
              <span>대화를 선택하거나 새로 만들어 채팅을 시작하세요.</span>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp chat_bubble_class(role) when role in [:user, "user"], do: "chat-bubble-primary"
  defp chat_bubble_class(role) when role in [:assistant, "assistant"], do: "chat-bubble-accent"

  defp chat_bubble_class(role) when role in [:tool, "tool"],
    do: "chat-bubble-warning"

  defp chat_bubble_class(_), do: ""

  defp role_label(role) when role in [:user, "user"], do: "You"
  defp role_label(role) when role in [:assistant, "assistant"], do: "Assistant"
  defp role_label(role) when role in [:tool, "tool"], do: "Tool Result"
  defp role_label(_), do: "System"

  defp find_agent_usage(usage_history, agent_id) do
    Enum.find(usage_history, fn usage ->
      usage.agent && usage.agent.id == agent_id
    end)
  end

  # Markdown을 HTML로 렌더링
  defp render_markdown(nil), do: Phoenix.HTML.raw("")

  defp render_markdown(content) when is_binary(content) do
    content
    |> Earmark.as_html!(@earmark_options)
    |> Phoenix.HTML.raw()
  end

  defp render_markdown(_), do: Phoenix.HTML.raw("")

  # MCP 상태 표시기 스타일
  defp mcp_status_indicator_class(status) do
    base = "flex items-center justify-center w-5 h-5 rounded-full"

    case status do
      :ready -> "#{base} bg-success/20"
      :unavailable -> "#{base} bg-error/20"
      :unknown -> "#{base} bg-base-content/10"
      _ -> "#{base} bg-base-content/10"
    end
  end

  defp mcp_status_dot_class(status) do
    base = "w-2.5 h-2.5 rounded-full"

    case status do
      :ready -> "#{base} bg-success shadow-lg shadow-success/50"
      :unavailable -> "#{base} bg-error shadow-lg shadow-error/50"
      :unknown -> "#{base} bg-base-content/30"
      _ -> "#{base} bg-base-content/30"
    end
  end

  defp mcp_status_label(status) do
    case status do
      :ready -> "사용 가능"
      :unavailable -> "환경 변수 미설정"
      :unknown -> "상태 확인 불가"
      _ -> "알 수 없음"
    end
  end

  # 사용자 프로필 조회 (표시용)
  # AI Agent가 대화를 통해 프로필을 수집하므로 팝업 없이 표시만 함
  defp get_user_profile_for_display do
    case MemoryManager.get_user_profile() do
      {:ok, profile} ->
        # 프로필이 완전한지 확인
        has_user_name = Map.get(profile, "user_name") || Map.get(profile, :user_name)
        has_agent_name = Map.get(profile, "agent_name") || Map.get(profile, :agent_name)
        has_city = Map.get(profile, "city") || Map.get(profile, :city)

        if has_user_name && has_agent_name && has_city do
          profile
        else
          nil
        end

      {:error, _} ->
        nil
    end
  end
end
