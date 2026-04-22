defmodule WebWeb.ChatLive do
  use WebWeb, :live_view

  alias Core.Schema.{Conversation, Message}
  alias Core.Repo
  alias Core.Agent.{Supervisor, SupervisorAgent}
  alias Core.Contexts.{Agents, Conversations, Mcps}

  import Ecto.Query

  @earmark_options %Earmark.Options{
    code_class_prefix: "language-",
    smartypants: false,
    breaks: true
  }

  @max_upload_entries 5
  # 10MB
  @max_upload_size 10_000_000
  @accepted_extensions ~w(.txt .md .pdf .png .jpg .jpeg .webp .json .csv .log)

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    conversations = Conversations.list_conversations(user.id)
    available_agents = Agents.list_agents(status: :active)
    available_mcps = Mcps.list_mcps_with_status()

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
      |> assign(:message_sent_at, nil)
      |> assign(:streaming_content, "")
      |> assign(:streaming_message_id, nil)
      |> assign(:streaming_status, nil)
      |> allow_upload(:attachments,
        accept: @accepted_extensions,
        max_entries: @max_upload_entries,
        max_file_size: @max_upload_size
      )

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    user = socket.assigns.current_user

    case Conversations.get_conversation(user.id, id) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "대화를 찾을 수 없습니다.")
         |> push_navigate(to: ~p"/chat")}

      conversation ->
        messages = list_messages(id)
        ensure_agent_started(id)

        socket =
          socket
          |> assign(:current_conversation, conversation)
          |> assign(:messages, messages)
          |> assign(:agent_usage_history, [])
          |> assign(:message_sent_at, nil)

        {:noreply, socket}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("new_conversation", _params, socket) do
    user = socket.assigns.current_user

    {:ok, conversation} =
      %Conversation{}
      |> Conversation.changeset(%{
        title: "New Chat #{DateTime.utc_now() |> DateTime.to_string()}",
        user_id: user.id
      })
      |> Repo.insert()

    socket =
      socket
      |> assign(:conversations, Conversations.list_conversations(user.id))
      |> push_navigate(to: ~p"/chat/#{conversation.id}")

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_conversation", %{"id" => id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/chat/#{id}")}
  end

  @impl true
  def handle_event("delete_conversation", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    case Conversations.get_conversation(user.id, id) do
      nil ->
        {:noreply, put_flash(socket, :error, "대화를 찾을 수 없습니다.")}

      conversation ->
        case Registry.lookup(Core.Agent.Registry, {:supervisor, id}) do
          [{pid, _}] -> Supervisor.stop_agent(pid)
          _ -> :ok
        end

        Message
        |> where([m], m.conversation_id == ^id)
        |> Repo.delete_all()

        Repo.delete!(conversation)

        socket =
          if socket.assigns.current_conversation && socket.assigns.current_conversation.id == id do
            socket
            |> assign(:conversations, Conversations.list_conversations(user.id))
            |> assign(:current_conversation, nil)
            |> assign(:messages, [])
            |> push_navigate(to: ~p"/chat")
          else
            assign(socket, :conversations, Conversations.list_conversations(user.id))
          end

        {:noreply, put_flash(socket, :info, "대화가 삭제되었습니다.")}
    end
  end

  @impl true
  def handle_event("update_input", %{"message" => value}, socket) do
    {:noreply, assign(socket, :input, value)}
  end

  @impl true
  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :attachments, ref)}
  end

  @impl true
  def handle_event("send_message", _params, socket) do
    input = String.trim(socket.assigns.input)

    cond do
      is_nil(socket.assigns.current_conversation) ->
        {:noreply, socket}

      input == "" and socket.assigns.uploads.attachments.entries == [] ->
        {:noreply, socket}

      true ->
        conversation_id = socket.assigns.current_conversation.id
        now = DateTime.utc_now() |> DateTime.truncate(:second)
        streaming_message_id = Ecto.UUID.generate()

        attachments = save_uploaded_files(socket, conversation_id)
        full_message = build_llm_message(input, attachments)

        user_message_record = %{
          id: Ecto.UUID.generate(),
          role: :user,
          content: input,
          attachments: attachments,
          inserted_at: now
        }

        # 영구 저장
        {:ok, _} =
          Conversations.create_message(%{
            role: :user,
            content: input,
            attachments: attachments,
            conversation_id: conversation_id
          })

        socket =
          socket
          |> assign(:messages, socket.assigns.messages ++ [user_message_record])
          |> assign(:input, "")
          |> assign(:loading, true)
          |> assign(:message_sent_at, now)
          |> assign(:agent_usage_history, [])
          |> assign(:streaming_content, "")
          |> assign(:streaming_message_id, streaming_message_id)
          |> assign(:streaming_status, :streaming)

        send(self(), {:process_message_stream, conversation_id, full_message})
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:process_message_stream, conversation_id, input}, socket) do
    liveview_pid = self()

    Task.start(fn ->
      try do
        case SupervisorAgent.stream_chat(conversation_id, input, liveview_pid) do
          {:ok, _response} -> :ok
          {:error, reason} -> send(liveview_pid, {:stream_error, conversation_id, reason})
        end
      catch
        # GenServer.call 타임아웃/exit 등으로 Task 가 죽으면 LiveView 가
        # "실시간 응답 중" 상태에 영구히 머무르므로 명시적으로 오류를 알린다.
        :exit, reason ->
          send(liveview_pid, {:stream_error, conversation_id, {:exit, reason}})

        kind, reason ->
          send(liveview_pid, {:stream_error, conversation_id, {kind, reason}})
      end
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:stream_chunk, conversation_id, text}, socket) do
    if current?(socket, conversation_id) do
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
    if current?(socket, conversation_id) do
      {:noreply, assign(socket, :streaming_status, {:tool_executing, tool_names})}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:stream_tool_end, conversation_id}, socket) do
    if current?(socket, conversation_id) do
      {:noreply, assign(socket, :streaming_status, :streaming)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:stream_postprocess, conversation_id}, socket) do
    if current?(socket, conversation_id) do
      {:noreply, assign(socket, :streaming_status, :postprocessing)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:stream_finish, conversation_id}, socket) do
    if current?(socket, conversation_id) do
      {:noreply, assign(socket, :streaming_status, :finishing)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:stream_error, conversation_id, reason}, socket) do
    if current?(socket, conversation_id) do
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

  @impl true
  def handle_info({:stream_complete, conversation_id, final_response}, socket) do
    if current?(socket, conversation_id) do
      assistant_message = %{
        id: socket.assigns.streaming_message_id,
        role: :assistant,
        content: final_response,
        attachments: [],
        inserted_at: DateTime.utc_now()
      }

      agent_usage_history =
        Agents.list_agent_usage_history(conversation_id, socket.assigns.message_sent_at)

      socket =
        socket
        |> assign(:messages, socket.assigns.messages ++ [assistant_message])
        |> assign(:loading, false)
        |> assign(:streaming_content, "")
        |> assign(:streaming_message_id, nil)
        |> assign(:streaming_status, nil)
        |> assign(:agent_usage_history, agent_usage_history)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  ## 비공개 헬퍼

  defp current?(socket, conversation_id) do
    socket.assigns.current_conversation &&
      socket.assigns.current_conversation.id == conversation_id
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
        case Agents.get_active_supervisor() do
          nil -> :ok
          supervisor -> Supervisor.start_supervisor_agent(supervisor.id, conversation_id)
        end

      _ ->
        :ok
    end
  end

  defp save_uploaded_files(socket, conversation_id) do
    workspace_dir = Application.get_env(:core, :workspace_dir) || "./workspace"
    dir = Path.join(workspace_dir, conversation_id)
    File.mkdir_p!(dir)

    consume_uploaded_entries(socket, :attachments, fn %{path: tmp_path}, entry ->
      ext = Path.extname(entry.client_name)
      unique_name = "#{Ecto.UUID.generate()}_#{sanitize(entry.client_name)}"
      dest = Path.join(dir, unique_name)
      File.cp!(tmp_path, dest)

      {:ok,
       %{
         "filename" => entry.client_name,
         "stored_path" => dest,
         "content_type" => entry.client_type,
         "size" => entry.client_size,
         "extension" => ext
       }}
    end)
  end

  defp sanitize(name) do
    name
    |> String.replace(~r/[^A-Za-z0-9._-]/, "_")
    |> String.slice(0, 80)
  end

  defp build_llm_message(input, []), do: input

  defp build_llm_message(input, attachments) do
    file_list =
      attachments
      |> Enum.map(fn a ->
        "- #{a["filename"]} (#{a["content_type"]}, #{format_bytes(a["size"])})\n  경로: #{a["stored_path"]}"
      end)
      |> Enum.join("\n")

    """
    #{input}

    [첨부 파일 #{length(attachments)}개]
    #{file_list}

    (필요 시 file_system 도구로 위 경로의 파일을 읽어 분석하세요.)
    """
  end

  defp format_bytes(nil), do: "?"
  defp format_bytes(b) when b < 1024, do: "#{b} B"
  defp format_bytes(b) when b < 1_048_576, do: "#{Float.round(b / 1024, 1)} KB"
  defp format_bytes(b), do: "#{Float.round(b / 1_048_576, 1)} MB"

  ## 렌더

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-[calc(100vh-4rem)] bg-base-100">
      <aside class="w-64 shrink-0 bg-base-200 flex flex-col border-r border-base-300">
        <div class="p-3 border-b border-base-300">
          <button phx-click="new_conversation" class="btn btn-primary btn-block btn-sm gap-2">
            <.icon name="hero-plus" class="size-4" /> 새 대화
          </button>
        </div>

        <ul class="menu menu-sm flex-1 overflow-y-auto p-2 gap-1">
          <%= for conv <- @conversations do %>
            <% active? = @current_conversation && @current_conversation.id == conv.id %>
            <li class="group">
              <a
                phx-click="select_conversation"
                phx-value-id={conv.id}
                class={["pr-1", active? && "menu-active"]}
              >
                <div class="flex-1 min-w-0">
                  <div class="truncate text-sm font-medium">{conv.title}</div>
                  <div class="text-xs opacity-50">
                    {Calendar.strftime(conv.inserted_at, "%Y-%m-%d %H:%M")}
                  </div>
                </div>
                <button
                  phx-click="delete_conversation"
                  phx-value-id={conv.id}
                  data-confirm="이 대화를 삭제하시겠습니까?"
                  class="btn btn-ghost btn-xs btn-circle text-error opacity-0 group-hover:opacity-100"
                  title="대화 삭제"
                >
                  <.icon name="hero-trash" class="size-4" />
                </button>
              </a>
            </li>
          <% end %>
        </ul>

        <ul class="menu menu-xs border-t border-base-300 p-2">
          <li class="menu-title">사용 가능한 MCP</li>
          <%= if @available_mcps == [] do %>
            <li class="disabled">
              <span class="italic opacity-50">설정된 MCP가 없습니다</span>
            </li>
          <% else %>
            <%= for mcp <- @available_mcps do %>
              <li>
                <div class="items-center">
                  <span
                    class={["status", mcp_status_class(mcp.status)]}
                    title={mcp_status_label(mcp.status)}
                  />
                  <div class="flex-1 min-w-0">
                    <div class="truncate font-medium">{mcp.name}</div>
                    <div class="truncate text-xs opacity-50">
                      {mcp.command} {Enum.join(mcp.args, " ")}
                    </div>
                  </div>
                </div>
              </li>
            <% end %>
          <% end %>
        </ul>

        <ul class="menu menu-xs border-t border-base-300 p-2">
          <li class="menu-title">사용 가능한 에이전트</li>
          <%= for agent <- @available_agents do %>
            <% usage_info = find_agent_usage(@agent_usage_history, agent.id) %>
            <li>
              <div class={["items-center", usage_info && "menu-active"]}>
                <%= if usage_info do %>
                  <span class="badge badge-primary badge-sm font-bold">{usage_info.order}</span>
                <% else %>
                  <span class="badge badge-ghost badge-sm">-</span>
                <% end %>
                <div class="flex-1 min-w-0">
                  <div class="truncate font-medium">{agent.display_name || agent.name}</div>
                  <div :if={agent.description} class="truncate text-xs opacity-50">
                    {agent.description}
                  </div>
                </div>
                <.icon :if={usage_info} name="hero-check-circle" class="size-4 text-success" />
              </div>
            </li>
          <% end %>
        </ul>
      </aside>

      <section class="flex-1 flex flex-col min-w-0">
        <div class="navbar bg-base-100 border-b border-base-300 shadow-sm min-h-14 px-4">
          <div class="flex-1 flex-col items-start">
            <h1 class="text-xl font-semibold">
              {if @current_conversation,
                do: @current_conversation.title,
                else: "Agentic AI Assistant"}
            </h1>
            <p class="text-xs text-base-content/50">Powered by Azure OpenAI</p>
          </div>
          <div class="flex-none">
            <button
              :if={@current_conversation}
              phx-click="delete_conversation"
              phx-value-id={@current_conversation.id}
              data-confirm="이 대화를 삭제하시겠습니까?"
              class="btn btn-ghost btn-sm text-error gap-2"
            >
              <.icon name="hero-trash" class="size-4" /> 삭제
            </button>
          </div>
        </div>

        <div class="flex-1 overflow-y-auto p-4 space-y-2" id="messages">
          <div :if={@messages == [] and @current_conversation} class="hero min-h-[50vh]">
            <div class="hero-content text-center">
              <div class="max-w-md">
                <h2 class="text-2xl font-bold">대화를 시작하세요!</h2>
                <p class="py-4 text-base-content/60">
                  AI 어시스턴트가 다양한 도구를 활용해 도움을 드립니다.
                </p>
              </div>
            </div>
          </div>

          <div
            :for={message <- @messages}
            class={["chat", chat_align_class(message.role)]}
          >
            <div class="chat-header text-xs opacity-60 mb-1">{role_label(message.role)}</div>
            <div class={["chat-bubble", chat_bubble_class(message.role)]}>
              <%= if message.role in [:assistant, "assistant"] do %>
                <div class="prose prose-sm max-w-none">
                  {render_markdown(message.content)}
                </div>
              <% else %>
                <div class="whitespace-pre-wrap">{message.content}</div>
              <% end %>
              <.attachments_list attachments={Map.get(message, :attachments) || []} />
            </div>
          </div>

          <%= if @loading do %>
            <%= if @streaming_content != "" or @streaming_status do %>
              <div class="chat chat-start">
                <div class="chat-header text-xs opacity-60 mb-1 flex items-center gap-2">
                  Assistant
                  <.streaming_status_badge status={@streaming_status} />
                </div>
                <div class="chat-bubble chat-bubble-accent">
                  <%= if @streaming_content != "" do %>
                    <div class="prose prose-sm max-w-none">
                      {render_markdown(@streaming_content)}
                    </div>
                    <span class="inline-block w-2 h-4 bg-primary animate-pulse ml-1" />
                  <% else %>
                    <span class="loading loading-dots loading-md" />
                  <% end %>
                </div>
              </div>
            <% else %>
              <div class="chat chat-start">
                <div class="chat-bubble chat-bubble-accent">
                  <span class="loading loading-dots loading-md" />
                </div>
              </div>
            <% end %>
          <% end %>
        </div>

        <%= if @current_conversation do %>
          <div class="bg-base-100 border-t border-base-300 p-4 space-y-2">
            <form
              id="chat-form"
              phx-submit="send_message"
              phx-change="validate_upload"
              class="space-y-2"
            >
              <div :if={@uploads.attachments.entries != []} class="flex flex-wrap gap-2">
                <div
                  :for={entry <- @uploads.attachments.entries}
                  class="badge badge-lg badge-outline gap-2"
                >
                  <.icon name="hero-paper-clip" class="size-3" />
                  <span class="text-xs">{entry.client_name}</span>
                  <span :if={entry.progress > 0 and entry.progress < 100} class="text-xs opacity-60">
                    {entry.progress}%
                  </span>
                  <button
                    type="button"
                    phx-click="cancel_upload"
                    phx-value-ref={entry.ref}
                    class="btn btn-ghost btn-xs btn-circle"
                    aria-label="첨부 취소"
                  >
                    ×
                  </button>
                </div>
              </div>
              <div
                :for={err <- upload_errors(@uploads.attachments)}
                role="alert"
                class="alert alert-error alert-soft py-2 text-xs"
              >
                <.icon name="hero-exclamation-triangle" class="size-4" />
                <span>{error_to_string(err)}</span>
              </div>

              <div class="join w-full">
                <label class="btn btn-ghost join-item" title="파일 첨부">
                  <.icon name="hero-paper-clip" class="size-5" />
                  <.live_file_input upload={@uploads.attachments} class="hidden" />
                </label>
                <input
                  type="text"
                  name="message"
                  value={@input}
                  phx-change="update_input"
                  placeholder="메시지를 입력하세요..."
                  disabled={@loading}
                  class="input join-item flex-1"
                  autocomplete="off"
                />
                <button type="submit" disabled={@loading} class="btn btn-primary join-item gap-2">
                  <.icon name="hero-paper-airplane" class="size-5" /> 전송
                </button>
              </div>
            </form>
          </div>
        <% else %>
          <div class="bg-base-100 border-t border-base-300 p-4">
            <div role="alert" class="alert alert-info alert-soft">
              <.icon name="hero-information-circle" class="size-5" />
              <span>대화를 선택하거나 새로 만들어 채팅을 시작하세요.</span>
            </div>
          </div>
        <% end %>
      </section>
    </div>
    """
  end

  attr :status, :any, required: true

  defp streaming_status_badge(%{status: :streaming} = assigns) do
    ~H"""
    <span class="badge badge-info badge-sm gap-1">
      <span class="loading loading-dots loading-xs" /> 실시간 응답 중
    </span>
    """
  end

  defp streaming_status_badge(%{status: {:tool_executing, _}} = assigns) do
    ~H"""
    <span class="badge badge-warning badge-sm gap-1">
      <span class="loading loading-spinner loading-xs" />
      {elem(@status, 1) |> Enum.join(", ")}
    </span>
    """
  end

  defp streaming_status_badge(%{status: :postprocessing} = assigns) do
    ~H"""
    <span class="badge badge-secondary badge-sm gap-1">
      <.icon name="hero-sparkles" class="size-3 animate-pulse" /> 응답 다듬는 중
    </span>
    """
  end

  defp streaming_status_badge(%{status: :finishing} = assigns) do
    ~H"""
    <span class="badge badge-success badge-sm gap-1">
      <.icon name="hero-check-circle" class="size-3" /> 완료 중
    </span>
    """
  end

  defp streaming_status_badge(assigns) do
    ~H"""
    <span class="badge badge-ghost badge-sm">처리 중</span>
    """
  end

  attr :attachments, :list, default: []

  defp attachments_list(assigns) do
    ~H"""
    <%= if @attachments != [] do %>
      <div class="mt-2 space-y-1">
        <%= for a <- @attachments do %>
          <div class="text-xs opacity-80 flex items-center gap-1">
            <.icon name="hero-paper-clip" class="w-3 h-3" />
            {Map.get(a, "filename") || Map.get(a, :filename)}
            <span class="opacity-50">
              ({format_bytes(Map.get(a, "size") || Map.get(a, :size))})
            </span>
          </div>
        <% end %>
      </div>
    <% end %>
    """
  end

  defp chat_align_class(role) when role in [:user, "user"], do: "chat-end"
  defp chat_align_class(_), do: "chat-start"

  defp chat_bubble_class(role) when role in [:user, "user"], do: "chat-bubble-primary"
  defp chat_bubble_class(role) when role in [:assistant, "assistant"], do: "chat-bubble-accent"
  defp chat_bubble_class(role) when role in [:tool, "tool"], do: "chat-bubble-warning"
  defp chat_bubble_class(_), do: ""

  defp role_label(role) when role in [:user, "user"], do: "You"
  defp role_label(role) when role in [:assistant, "assistant"], do: "Assistant"
  defp role_label(role) when role in [:tool, "tool"], do: "Tool Result"
  defp role_label(_), do: "System"

  defp find_agent_usage(usage_history, agent_id) do
    Enum.find(usage_history, fn usage -> usage.agent && usage.agent.id == agent_id end)
  end

  defp render_markdown(nil), do: Phoenix.HTML.raw("")

  defp render_markdown(content) when is_binary(content) do
    content
    |> Earmark.as_html!(@earmark_options)
    |> Phoenix.HTML.raw()
  end

  defp render_markdown(_), do: Phoenix.HTML.raw("")

  defp mcp_status_class(:ready), do: "status-success"
  defp mcp_status_class(:unavailable), do: "status-error"
  defp mcp_status_class(_), do: "status-neutral"

  defp mcp_status_label(:ready), do: "사용 가능"
  defp mcp_status_label(:unavailable), do: "사용 불가"
  defp mcp_status_label(_), do: "상태 미확인"

  defp error_to_string(:too_large), do: "파일이 너무 큽니다 (최대 10MB)."
  defp error_to_string(:too_many_files), do: "파일이 너무 많습니다 (최대 5개)."
  defp error_to_string(:not_accepted), do: "지원하지 않는 파일 형식입니다."
  defp error_to_string(err), do: "업로드 오류: #{inspect(err)}"
end
