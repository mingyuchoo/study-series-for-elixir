defmodule WebWeb.ChatLive do
  use WebWeb, :live_view

  alias Core.Agent.{Supervisor, SupervisorAgent}
  alias Core.Contexts.{Agents, Conversations, Mcps, VectorRags}
  alias Core.Repo
  alias Core.Schema.{Conversation, Message}

  import Ecto.Query

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
    available_knowledge = VectorRags.list_vector_rags_with_status()

    socket =
      socket
      |> assign(:conversations, conversations)
      |> assign(:current_conversation, nil)
      |> assign(:messages, [])
      |> assign(:input, "")
      |> assign(:loading, false)
      |> assign(:available_agents, available_agents)
      |> assign(:available_mcps, available_mcps)
      |> assign(:available_knowledge, available_knowledge)
      |> assign(:mcp_statuses, %{})
      |> assign(:knowledge_statuses, %{})
      |> assign(:agent_usage_history, [])
      |> assign(:message_sent_at, nil)
      |> assign(:streaming_content, "")
      |> assign(:streaming_message_id, nil)
      |> assign(:streaming_status, nil)
      |> assign(:agent_execution_failed, false)
      |> assign(:agent_statuses, %{})
      |> assign(:debate_active, false)
      |> assign(:debate_round, 0)
      |> assign(:debate_max_rounds, 0)
      |> assign(:current_speaker, nil)
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
          |> assign(:agent_execution_failed, false)
          |> assign(:agent_statuses, %{})
          |> assign(:mcp_statuses, %{})
          |> assign(:knowledge_statuses, %{})
          |> assign(:message_sent_at, nil)
          |> assign(:debate_active, false)
          |> assign(:debate_round, 0)
          |> assign(:debate_max_rounds, 0)
          |> assign(:current_speaker, nil)

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
          |> assign(:messages, List.insert_at(socket.assigns.messages, -1, user_message_record))
          |> assign(:input, "")
          |> assign(:loading, true)
          |> assign(:message_sent_at, now)
          |> assign(:agent_usage_history, [])
          |> assign(:agent_execution_failed, false)
          |> assign(:agent_statuses, %{})
          |> assign(:mcp_statuses, %{})
          |> assign(:knowledge_statuses, %{})
          |> assign(:streaming_content, "")
          |> assign(:streaming_message_id, streaming_message_id)
          |> assign(:streaming_status, :streaming)
          |> assign(:debate_active, false)
          |> assign(:debate_round, 0)
          |> assign(:debate_max_rounds, 0)
          |> assign(:current_speaker, default_assistant_agent(socket))

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
      socket =
        socket
        |> assign(:streaming_status, {:tool_executing, tool_names})
        |> assign(:mcp_statuses, set_mcp_statuses(socket, tool_names, :running))
        |> assign(:knowledge_statuses, set_knowledge_statuses(socket, tool_names, :running))

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:stream_tool_end, conversation_id, tool_names, failed_tool_names}, socket) do
    if current?(socket, conversation_id) do
      socket =
        socket
        |> assign(:streaming_status, :streaming)
        |> assign(:mcp_statuses, complete_mcp_statuses(socket, tool_names, failed_tool_names))
        |> assign(
          :knowledge_statuses,
          complete_knowledge_statuses(socket, tool_names, failed_tool_names)
        )

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:stream_tool_end, conversation_id}, socket) do
    if current?(socket, conversation_id) do
      socket =
        socket
        |> assign(:streaming_status, :streaming)
        |> assign(:mcp_statuses, mark_running_mcps_idle(socket.assigns.mcp_statuses))
        |> assign(
          :knowledge_statuses,
          mark_running_knowledge_idle(socket.assigns.knowledge_statuses)
        )

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:agent_status, conversation_id, agent_name, status}, socket) do
    if current?(socket, conversation_id) do
      socket =
        socket
        |> assign(:agent_statuses, set_agent_status(socket, agent_name, status))
        |> maybe_set_current_speaker(agent_name, status)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(
        {:debate_started, conversation_id, %{max_rounds: max_rounds}},
        socket
      ) do
    if current?(socket, conversation_id) do
      socket =
        socket
        |> assign(:debate_active, true)
        |> assign(:debate_round, 0)
        |> assign(:debate_max_rounds, max_rounds)
        |> assign(:current_speaker, default_assistant_agent(socket))

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:debate_message_inserted, conversation_id, message}, socket) do
    if current?(socket, conversation_id) do
      # 그룹 채팅 라운드 카운터: debate_turn 메시지가 모더레이터의 발언자 지명일 때 증가
      new_round =
        if message.visibility == :debate_turn and supervisor_message?(message) do
          socket.assigns.debate_round + 1
        else
          socket.assigns.debate_round
        end

      socket =
        socket
        |> assign(:messages, List.insert_at(socket.assigns.messages, -1, message))
        |> assign(:streaming_content, "")
        |> assign(:debate_round, new_round)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:debate_finished, conversation_id, _final_answer}, socket) do
    if current?(socket, conversation_id) do
      agent_usage_history =
        Agents.list_agent_usage_history(conversation_id, socket.assigns.message_sent_at)

      socket =
        socket
        |> assign(:loading, false)
        |> assign(:streaming_content, "")
        |> assign(:streaming_message_id, nil)
        |> assign(:streaming_status, nil)
        |> assign(:debate_active, false)
        |> assign(:current_speaker, nil)
        |> assign(:agent_usage_history, agent_usage_history)
        |> assign(
          :agent_statuses,
          finalize_agent_statuses(socket.assigns.agent_statuses, false)
        )
        |> assign(
          :mcp_statuses,
          finalize_mcp_statuses(socket.assigns.mcp_statuses, false)
        )
        |> assign(
          :knowledge_statuses,
          finalize_knowledge_statuses(socket.assigns.knowledge_statuses, false)
        )

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:debate_speaker_finishing, conversation_id, agent_name}, socket) do
    if current?(socket, conversation_id) do
      socket =
        socket
        |> assign(:streaming_status, :finishing)
        |> assign(
          :agent_statuses,
          set_agent_status(socket, agent_name, :finishing)
        )
        |> maybe_set_current_speaker(agent_name, :finishing)

      {:noreply, socket}
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
        |> assign(:agent_execution_failed, true)
        |> assign(:agent_statuses, mark_running_agents_failed(socket.assigns.agent_statuses))
        |> assign(:mcp_statuses, mark_running_mcps_failed(socket.assigns.mcp_statuses))
        |> assign(
          :knowledge_statuses,
          mark_running_knowledge_failed(socket.assigns.knowledge_statuses)
        )
        |> put_flash(:error, "스트리밍 오류: #{inspect(reason)}")

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:stream_complete, conversation_id, final_response}, socket) do
    if current?(socket, conversation_id) do
      agent_execution_failed = agent_response_error?(final_response)

      # 그룹 채팅이 활성 상태였다면 :debate_message_inserted 가 이미 메시지를 추가했고
      # :debate_finished 가 정리를 처리합니다. 여기서는 중복 추가하지 않습니다.
      # 비그룹채팅 경로(프로필 수집 등)에서만 메시지를 추가합니다.
      already_persisted? =
        socket.assigns.debate_active or last_message_matches?(socket, final_response)

      messages =
        if already_persisted? do
          socket.assigns.messages
        else
          assistant_message = %{
            id: socket.assigns.streaming_message_id,
            role: :assistant,
            content: final_response,
            attachments: [],
            agent: socket.assigns.current_speaker || default_assistant_agent(socket),
            inserted_at: DateTime.utc_now()
          }

          List.insert_at(socket.assigns.messages, -1, assistant_message)
        end

      agent_usage_history =
        Agents.list_agent_usage_history(conversation_id, socket.assigns.message_sent_at)

      socket =
        socket
        |> assign(:messages, messages)
        |> assign(:loading, false)
        |> assign(:streaming_content, "")
        |> assign(:streaming_message_id, nil)
        |> assign(:streaming_status, nil)
        |> assign(:agent_usage_history, agent_usage_history)
        |> assign(:agent_execution_failed, agent_execution_failed)
        |> assign(
          :agent_statuses,
          finalize_agent_statuses(socket.assigns.agent_statuses, agent_execution_failed)
        )
        |> assign(
          :mcp_statuses,
          finalize_mcp_statuses(socket.assigns.mcp_statuses, agent_execution_failed)
        )
        |> assign(
          :knowledge_statuses,
          finalize_knowledge_statuses(socket.assigns.knowledge_statuses, agent_execution_failed)
        )

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  defp last_message_matches?(socket, content) do
    case List.last(socket.assigns.messages) do
      %{content: ^content} -> true
      _ -> false
    end
  end

  defp maybe_set_current_speaker(socket, agent_name, status)
       when status in [:running, :finishing] do
    speaker = Enum.find(socket.assigns.available_agents, &(&1.name == agent_name))
    assign(socket, :current_speaker, speaker)
  end

  defp maybe_set_current_speaker(socket, _agent_name, _status), do: socket

  defp supervisor_message?(%{agent: %{type: :supervisor}}), do: true
  defp supervisor_message?(_), do: false

  ## 비공개 헬퍼

  defp current?(socket, conversation_id) do
    socket.assigns.current_conversation &&
      socket.assigns.current_conversation.id == conversation_id
  end

  defp set_agent_status(socket, agent_name, status)
       when is_binary(agent_name) and status in [:running, :finishing, :idle, :error] do
    known_agent? = Enum.any?(socket.assigns.available_agents, &(&1.name == agent_name))

    if known_agent? do
      Map.put(socket.assigns.agent_statuses, agent_name, status)
    else
      socket.assigns.agent_statuses
    end
  end

  defp set_agent_status(socket, _agent_name, _status), do: socket.assigns.agent_statuses

  defp set_mcp_statuses(socket, tool_names, status) when is_list(tool_names) do
    tool_names
    |> Enum.map(&tool_mcp_name/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&known_mcp?(socket, &1))
    |> Enum.reduce(socket.assigns.mcp_statuses, fn mcp_name, statuses ->
      Map.put(statuses, mcp_name, status)
    end)
  end

  defp set_mcp_statuses(socket, _tool_names, _status), do: socket.assigns.mcp_statuses

  defp complete_mcp_statuses(socket, tool_names, failed_tool_names) do
    failed_mcps =
      failed_tool_names
      |> Enum.map(&tool_mcp_name/1)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    tool_names
    |> Enum.map(&tool_mcp_name/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&known_mcp?(socket, &1))
    |> Enum.reduce(socket.assigns.mcp_statuses, fn mcp_name, statuses ->
      if MapSet.member?(failed_mcps, mcp_name) do
        Map.put(statuses, mcp_name, :error)
      else
        Map.put(statuses, mcp_name, :idle)
      end
    end)
  end

  defp known_mcp?(socket, mcp_name) do
    Enum.any?(socket.assigns.available_mcps, &(&1.name == mcp_name))
  end

  defp set_knowledge_statuses(socket, tool_names, status) when is_list(tool_names) do
    if Enum.any?(tool_names, &(&1 == "search_vector_rag")) do
      socket.assigns.available_knowledge
      |> Enum.filter(&(&1.status == :ready))
      |> Enum.reduce(socket.assigns.knowledge_statuses, fn knowledge, statuses ->
        Map.put(statuses, knowledge.name, status)
      end)
    else
      socket.assigns.knowledge_statuses
    end
  end

  defp set_knowledge_statuses(socket, _tool_names, _status), do: socket.assigns.knowledge_statuses

  defp complete_knowledge_statuses(socket, tool_names, failed_tool_names) do
    cond do
      not Enum.any?(tool_names, &(&1 == "search_vector_rag")) ->
        socket.assigns.knowledge_statuses

      Enum.any?(failed_tool_names, &(&1 == "search_vector_rag")) ->
        mark_running_knowledge_failed(socket.assigns.knowledge_statuses)

      true ->
        mark_running_knowledge_idle(socket.assigns.knowledge_statuses)
    end
  end

  defp tool_mcp_name(tool_name) when is_binary(tool_name) do
    cond do
      String.starts_with?(tool_name, "firecrawl_") -> "firecrawl"
      String.starts_with?(tool_name, "mcp__firecrawl__") -> "firecrawl"
      String.starts_with?(tool_name, "mcp_filesystem_") -> "filesystem"
      String.starts_with?(tool_name, "mcp_desktop_commander_") -> "desktop-commander"
      true -> nil
    end
  end

  defp tool_mcp_name(_tool_name), do: nil

  defp mark_running_agents_failed(agent_statuses) do
    Map.new(agent_statuses, fn
      {agent_name, status} when status in [:running, :finishing] -> {agent_name, :error}
      entry -> entry
    end)
  end

  defp finalize_agent_statuses(agent_statuses, true),
    do: mark_running_agents_failed(agent_statuses)

  defp finalize_agent_statuses(agent_statuses, false) do
    Map.new(agent_statuses, fn
      {agent_name, status} when status in [:running, :finishing] -> {agent_name, :idle}
      entry -> entry
    end)
  end

  defp mark_running_mcps_failed(mcp_statuses) do
    Map.new(mcp_statuses, fn
      {mcp_name, :running} -> {mcp_name, :error}
      entry -> entry
    end)
  end

  defp mark_running_mcps_idle(mcp_statuses) do
    Map.new(mcp_statuses, fn
      {mcp_name, :running} -> {mcp_name, :idle}
      entry -> entry
    end)
  end

  defp finalize_mcp_statuses(mcp_statuses, true), do: mark_running_mcps_failed(mcp_statuses)
  defp finalize_mcp_statuses(mcp_statuses, false), do: mark_running_mcps_idle(mcp_statuses)

  defp mark_running_knowledge_failed(knowledge_statuses) do
    Map.new(knowledge_statuses, fn
      {knowledge_name, :running} -> {knowledge_name, :error}
      entry -> entry
    end)
  end

  defp mark_running_knowledge_idle(knowledge_statuses) do
    Map.new(knowledge_statuses, fn
      {knowledge_name, :running} -> {knowledge_name, :idle}
      entry -> entry
    end)
  end

  defp finalize_knowledge_statuses(knowledge_statuses, true),
    do: mark_running_knowledge_failed(knowledge_statuses)

  defp finalize_knowledge_statuses(knowledge_statuses, false),
    do: mark_running_knowledge_idle(knowledge_statuses)

  defp list_messages(conversation_id) do
    Message
    |> where([m], m.conversation_id == ^conversation_id)
    |> order_by([m], asc: m.inserted_at)
    |> Repo.all()
    |> Repo.preload(:agent)
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
      Enum.map_join(attachments, "\n", fn a ->
        "- #{a["filename"]} (#{a["content_type"]}, #{format_bytes(a["size"])})\n  경로: #{a["stored_path"]}"
      end)

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
      <aside class="flex w-64 shrink-0 flex-col border-r border-base-300 bg-base-200">
        <div class="p-3 border-b border-base-300">
          <button phx-click="new_conversation" class="btn btn-primary btn-block btn-sm gap-2">
            <.icon name="hero-plus" class="size-4" /> 새 대화
          </button>
        </div>

        <ul class="menu menu-sm flex-1 w-full overflow-y-auto p-2 gap-1">
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
                  class="btn btn-ghost btn-xs text-error opacity-0 group-hover:opacity-100"
                  title="대화 삭제"
                >
                  <.icon name="hero-trash" class="size-4" />
                </button>
              </a>
            </li>
          <% end %>
        </ul>

        <ul class="menu menu-xs w-full border-t border-base-300 p-2">
          <li class="menu-title">사용 가능한 에이전트</li>
          <%= for agent <- @available_agents do %>
            <% agent_status = Map.get(@agent_statuses, agent.name, :idle) %>
            <li class="w-full">
              <div class="flex items-center gap-2 w-full">
                <img
                  src={agent_avatar_url(agent)}
                  alt={agent.display_name || agent.name}
                  class="h-7 w-7 shrink-0 object-cover ring-1 ring-base-300"
                />
                <span
                  class={[
                    "status shrink-0",
                    agent_status_class(agent_status)
                  ]}
                  title={agent_status_label(agent_status)}
                />
                <div class="flex-1 min-w-0">
                  <div class="truncate font-medium">{agent.display_name || agent.name}</div>
                  <div :if={agent.description} class="truncate text-xs opacity-50">
                    {agent.description}
                  </div>
                </div>
              </div>
            </li>
          <% end %>
        </ul>

        <ul class="menu menu-xs w-full border-t border-base-300 p-2">
          <li class="menu-title">사용 가능한 지식</li>
          <%= if @available_knowledge == [] do %>
            <li class="disabled">
              <span class="italic opacity-50">설정된 지식이 없습니다</span>
            </li>
          <% else %>
            <%= for knowledge <- @available_knowledge do %>
              <% knowledge_runtime_status = Map.get(@knowledge_statuses, knowledge.name, :idle) %>
              <li class="w-full">
                <div class="flex items-center gap-2 w-full">
                  <span
                    class={[
                      "status shrink-0",
                      knowledge_status_class(knowledge.status, knowledge_runtime_status)
                    ]}
                    title={knowledge_status_label(knowledge.status, knowledge_runtime_status)}
                  />
                  <div class="flex-1 min-w-0">
                    <div class="truncate font-medium">{knowledge.name}</div>
                    <div class="truncate text-xs opacity-50">
                      {knowledge.chunk_count} chunks · {knowledge.source_filename || "문서"}
                    </div>
                  </div>
                </div>
              </li>
            <% end %>
          <% end %>
        </ul>

        <ul class="menu menu-xs w-full border-t border-base-300 p-2">
          <li class="menu-title">사용 가능한 MCP</li>
          <%= if @available_mcps == [] do %>
            <li class="disabled">
              <span class="italic opacity-50">설정된 MCP가 없습니다</span>
            </li>
          <% else %>
            <%= for mcp <- @available_mcps do %>
              <% mcp_runtime_status = Map.get(@mcp_statuses, mcp.name, :idle) %>
              <li class="w-full">
                <div class="flex items-center gap-2 w-full">
                  <span
                    class={["status shrink-0", mcp_status_class(mcp.status, mcp_runtime_status)]}
                    title={mcp_status_label(mcp.status, mcp_runtime_status)}
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
      </aside>

      <section class="flex min-w-0 flex-1 flex-col">
        <div class="navbar min-h-14 border-b border-base-300 bg-base-100 px-4">
          <div class="flex-1 flex-col items-start">
            <h1 class="text-xl font-normal">
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
                <h2 class="text-3xl font-light">대화를 시작하세요</h2>
                <p class="py-4 text-base-content/60">
                  AI 어시스턴트가 다양한 도구를 활용해 도움을 드립니다.
                </p>
              </div>
            </div>
          </div>

          <div
            :for={message <- @messages}
            class={["chat", chat_align_class(message)]}
          >
            <div :if={message_role(message) in [:assistant, "assistant"]} class="chat-image avatar">
              <div class="w-8 ring-1 ring-base-300">
                <img
                  src={message_avatar_url(message)}
                  alt={message_speaker_label(message)}
                />
              </div>
            </div>
            <div class="chat-header text-xs opacity-60 mb-1 flex items-center gap-1">
              <span class={message_speaker_class(message)}>{message_speaker_label(message)}</span>
              <span :if={debate_visibility_label(message)} class="badge badge-xs badge-ghost">
                {debate_visibility_label(message)}
              </span>
            </div>
            <div class={["chat-bubble", chat_bubble_class(message)]}>
              <%= if message_role(message) in [:assistant, "assistant"] do %>
                <div class="prose prose-sm max-w-none">
                  {render_markdown(message.content)}
                </div>
              <% else %>
                <div class="whitespace-pre-wrap">{message.content}</div>
              <% end %>
              <.attachments_list attachments={Map.get(message, :attachments) || []} />
            </div>
          </div>

          <%= if @debate_active do %>
            <div class="alert alert-info alert-soft py-2 mx-2 text-xs">
              <.icon name="hero-users" class="size-4" />
              <span>
                그룹 채팅 진행 중 · 라운드 {@debate_round} / {@debate_max_rounds}
                <%= if @current_speaker do %>
                  · 현재 발언자: <strong>{@current_speaker.display_name || @current_speaker.name}</strong>
                <% end %>
              </span>
            </div>
          <% end %>

          <%= if @loading do %>
            <%= if @streaming_content != "" or @streaming_status do %>
              <div class="chat chat-start">
                <div class="chat-image avatar">
                  <div class="w-8 ring-1 ring-base-300">
                    <img
                      src={speaker_avatar_url(@current_speaker)}
                      alt={speaker_streaming_label(@current_speaker)}
                    />
                  </div>
                </div>
                <div class="chat-header text-xs opacity-60 mb-1 flex items-center gap-2">
                  <span class="font-semibold text-info">
                    {speaker_streaming_label(@current_speaker)}
                  </span>
                  <.streaming_status_badge status={@streaming_status} />
                </div>
                <div class={["chat-bubble", speaker_chat_bubble_class(@current_speaker)]}>
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
                <div class="chat-image avatar">
                  <div class="w-8 ring-1 ring-base-300">
                    <img
                      src={speaker_avatar_url(@current_speaker)}
                      alt={speaker_streaming_label(@current_speaker)}
                    />
                  </div>
                </div>
                <div class={["chat-bubble", speaker_chat_bubble_class(@current_speaker)]}>
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
                    class="btn btn-ghost btn-xs"
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
                  id="chat-message-input"
                  phx-hook="ChatInputFocus"
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

  defp message_role(message), do: Map.get(message, :role)

  defp message_visibility(message), do: Map.get(message, :visibility, :user_facing)

  defp message_agent(message), do: Map.get(message, :agent)

  defp chat_align_class(message) do
    case message_role(message) do
      role when role in [:user, "user"] -> "chat-end"
      _ -> "chat-start"
    end
  end

  defp chat_bubble_class(message) do
    role = message_role(message)
    visibility = message_visibility(message)
    agent = message_agent(message)

    cond do
      role in [:user, "user"] ->
        "chat-bubble-primary"

      role in [:tool, "tool"] ->
        "chat-bubble-warning"

      visibility == :final ->
        "chat-bubble-accent"

      visibility == :debate_turn and is_map(agent) and agent.type == :supervisor ->
        # 모더레이터의 메타 메시지
        "chat-bubble-info"

      visibility == :debate_turn ->
        # 워커 발언
        "chat-bubble-secondary"

      true ->
        "chat-bubble-accent"
    end
  end

  defp message_speaker_label(message) do
    role = message_role(message)
    agent = message_agent(message)
    visibility = message_visibility(message)
    speaker_label(role, agent, visibility)
  end

  defp speaker_label(role, _agent, _visibility) when role in [:user, "user"], do: "You"
  defp speaker_label(role, _agent, _visibility) when role in [:tool, "tool"], do: "Tool"

  defp speaker_label(_role, %{type: :supervisor} = agent, :debate_turn) do
    "🎯 Moderator (#{agent.display_name || agent.name})"
  end

  defp speaker_label(_role, %{display_name: display_name}, _visibility)
       when is_binary(display_name) and display_name != "" do
    display_name
  end

  defp speaker_label(_role, %{name: name}, _visibility) when is_binary(name) and name != "",
    do: name

  defp speaker_label(role, _agent, _visibility) when role in [:assistant, "assistant"],
    do: "Assistant"

  defp speaker_label(_role, _agent, _visibility), do: "System"

  defp message_speaker_class(message) do
    case message_visibility(message) do
      :final -> "font-semibold text-accent"
      :debate_turn -> "font-medium text-base-content/80"
      _ -> ""
    end
  end

  defp debate_visibility_label(message) do
    case message_visibility(message) do
      :debate_turn -> "토론"
      :final -> "최종"
      _ -> nil
    end
  end

  defp speaker_streaming_label(nil), do: "Assistant"

  defp speaker_streaming_label(%{display_name: name}) when is_binary(name), do: name

  defp speaker_streaming_label(%{name: name}) when is_binary(name), do: name

  defp speaker_streaming_label(_), do: "Assistant"

  defp speaker_chat_bubble_class(%{type: :supervisor}), do: "chat-bubble-info"
  defp speaker_chat_bubble_class(%{type: "supervisor"}), do: "chat-bubble-info"
  defp speaker_chat_bubble_class(%{type: :worker}), do: "chat-bubble-secondary"
  defp speaker_chat_bubble_class(%{type: "worker"}), do: "chat-bubble-secondary"
  defp speaker_chat_bubble_class(_), do: "chat-bubble-accent"

  defp agent_response_error?(response) when is_binary(response) do
    String.starts_with?(response, "작업 수행 중 오류가 발생했습니다:")
  end

  defp agent_response_error?(_), do: false

  defp agent_status_class(:running), do: ["bg-green-500", "text-green-500"]
  defp agent_status_class(:finishing), do: ["bg-green-500", "text-green-500"]
  defp agent_status_class(:error), do: ["bg-red-500", "text-red-500"]
  defp agent_status_class(_), do: ["bg-orange-500", "text-orange-500"]

  defp knowledge_status_class(_configured_status, :running),
    do: ["bg-green-500", "text-green-500"]

  defp knowledge_status_class(_configured_status, :error), do: ["bg-red-500", "text-red-500"]
  defp knowledge_status_class(:ready, _runtime_status), do: ["bg-orange-500", "text-orange-500"]
  defp knowledge_status_class(:missing_index, _runtime_status), do: ["bg-red-500", "text-red-500"]
  defp knowledge_status_class(:disabled, _runtime_status), do: "status-neutral"
  defp knowledge_status_class(_configured_status, _runtime_status), do: "status-neutral"

  defp knowledge_status_label(_configured_status, :running), do: "검색 중"
  defp knowledge_status_label(_configured_status, :error), do: "오류"
  defp knowledge_status_label(:ready, _runtime_status), do: "대기"
  defp knowledge_status_label(:missing_index, _runtime_status), do: "인덱스 파일 없음"
  defp knowledge_status_label(:disabled, _runtime_status), do: "비활성"
  defp knowledge_status_label(_configured_status, _runtime_status), do: "비어 있음"

  defp agent_avatar_url(agent) do
    "/images/profiles/" <> agent_avatar_filename(agent)
  end

  defp message_avatar_url(message) do
    case message_agent(message) do
      agent when is_map(agent) -> agent_avatar_url(agent)
      _ -> agent_avatar_url(nil)
    end
  end

  # 비그룹채팅 응답 시 fallback. SupervisorAgent 가 DB 에 저장하는 agent_id 와
  # 동일한 main_supervisor 를 사용해 라벨/아바타가 일관되게 보이도록 한다.
  # available_agents 가 stale 하거나 supervisor 가 비활성이면 DB 에서 직접 조회한다.
  defp default_assistant_agent(socket) do
    Enum.find(socket.assigns.available_agents, &(&1.type == :supervisor)) ||
      Agents.get_active_supervisor()
  end

  defp speaker_avatar_url(agent) when is_map(agent), do: agent_avatar_url(agent)
  defp speaker_avatar_url(_), do: agent_avatar_url(nil)

  defp agent_avatar_filename(%{avatar_path: avatar_path})
       when is_binary(avatar_path) and avatar_path != "" do
    avatar_path
  end

  defp agent_avatar_filename(_agent), do: "avatar-07.png"

  defp agent_status_label(:running), do: "동작"
  defp agent_status_label(:finishing), do: "완료 중"
  defp agent_status_label(:error), do: "오류"
  defp agent_status_label(_), do: "대기"

  defp render_markdown(nil), do: Phoenix.HTML.raw("")

  defp render_markdown(content) when is_binary(content) do
    content
    |> MDEx.to_html!(render: [hardbreaks: true])
    |> Phoenix.HTML.raw()
  end

  defp render_markdown(_), do: Phoenix.HTML.raw("")

  defp mcp_status_class(_configured_status, :running), do: ["bg-green-500", "text-green-500"]
  defp mcp_status_class(_configured_status, :error), do: ["bg-red-500", "text-red-500"]
  defp mcp_status_class(:ready, _runtime_status), do: ["bg-orange-500", "text-orange-500"]
  defp mcp_status_class(:unavailable, _runtime_status), do: "status-error"
  defp mcp_status_class(_configured_status, _runtime_status), do: "status-neutral"

  defp mcp_status_label(_configured_status, :running), do: "동작"
  defp mcp_status_label(_configured_status, :error), do: "오류"
  defp mcp_status_label(:ready, _runtime_status), do: "대기"
  defp mcp_status_label(:unavailable, _runtime_status), do: "사용 불가"
  defp mcp_status_label(_configured_status, _runtime_status), do: "상태 미확인"

  defp error_to_string(:too_large), do: "파일이 너무 큽니다 (최대 10MB)."
  defp error_to_string(:too_many_files), do: "파일이 너무 많습니다 (최대 5개)."
  defp error_to_string(:not_accepted), do: "지원하지 않는 파일 형식입니다."
  defp error_to_string(err), do: "업로드 오류: #{inspect(err)}"
end
