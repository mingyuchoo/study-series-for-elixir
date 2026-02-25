defmodule Core.Agent.SupervisorAgent do
  @moduledoc """
  Supervisor 에이전트 GenServer.

  사용자 요청을 분석하고 적절한 Worker에게 작업을 전달합니다.
  Worker의 결과를 수집하여 사용자에게 응답합니다.
  새로운 사용자의 경우 능동적으로 프로필 정보를 수집합니다.
  """

  use GenServer
  require Logger

  alias Core.Agent.{Coordinator, MemoryManager, TaskRouter, WorkerAgent}
  alias Core.Contexts.Agents
  alias Core.Schema.{Agent, Message}
  alias Core.Repo

  # 프로필 수집 상태
  # :idle - 프로필 수집 중이 아님
  # :collecting_user_name - 사용자 이름 수집 중
  # :collecting_agent_name - AI 비서 이름 수집 중
  # :collecting_city - 도시 수집 중
  # :complete - 프로필 수집 완료
  defstruct [
    :agent_id,
    :agent,
    :conversation_id,
    :worker_agents,
    profile_state: :idle,
    partial_profile: %{}
  ]

  # 클라이언트 API

  @doc """
  SupervisorAgent 프로세스를 시작합니다.

  ## Options

    - `:agent_id` - Supervisor 에이전트 ID (필수)
    - `:conversation_id` - 대화 ID (필수)
  """
  def start_link(opts) do
    agent_id = Keyword.fetch!(opts, :agent_id)
    conversation_id = Keyword.fetch!(opts, :conversation_id)

    GenServer.start_link(__MODULE__, {agent_id, conversation_id},
      name: via_tuple(conversation_id)
    )
  end

  @doc """
  Supervisor에게 사용자 메시지를 전달합니다.

  ## Parameters

    - `conversation_id` - 대화 ID
    - `user_message` - 사용자 메시지

  ## Returns

    - `{:ok, response}` - 성공 시 응답
    - `{:error, reason}` - 실패 시 오류 원인
  """
  def chat(conversation_id, user_message) do
    GenServer.call(via_tuple(conversation_id), {:chat, user_message}, 180_000)
  end

  @doc """
  Supervisor에게 스트리밍 모드로 사용자 메시지를 전달합니다.

  ## Parameters

    - `conversation_id` - 대화 ID
    - `user_message` - 사용자 메시지
    - `liveview_pid` - 스트리밍 청크를 수신할 LiveView 프로세스 PID

  ## Returns

    - `{:ok, response}` - 성공 시 최종 응답
    - `{:error, reason}` - 실패 시 오류 원인
  """
  def stream_chat(conversation_id, user_message, liveview_pid) do
    GenServer.call(
      via_tuple(conversation_id),
      {:stream_chat, user_message, liveview_pid},
      180_000
    )
  end

  # 서버 콜백

  @impl true
  def init({agent_id, conversation_id}) do
    case Agents.get_agent(agent_id) do
      nil ->
        {:stop, {:error, :agent_not_found}}

      %Agent{type: :supervisor} = agent ->
        # Markdown에서 메모리 로드 시도
        load_memory_from_markdown(agent_id, agent.name)

        # 사용 가능한 Worker 로드
        worker_agents_data = Agents.list_workers()

        # Worker 프로세스 시작
        worker_agents = start_workers(worker_agents_data)

        # 프로필 상태 초기화
        {profile_state, partial_profile} = init_profile_state()

        state = %__MODULE__{
          agent_id: agent_id,
          agent: agent,
          conversation_id: conversation_id,
          worker_agents: worker_agents,
          profile_state: profile_state,
          partial_profile: partial_profile
        }

        Logger.info("SupervisorAgent started: #{agent.name} for conversation #{conversation_id}")

        Logger.info(
          "Available workers: #{inspect(Enum.map(worker_agents, fn {a, _} -> a.name end))}"
        )

        {:ok, state}

      %Agent{type: type} ->
        {:stop, {:error, {:invalid_agent_type, type}}}
    end
  end

  @impl true
  def handle_call({:chat, user_message}, _from, state) do
    Logger.info("SupervisorAgent received message: #{user_message}")

    # 프로필 수집 중인지 확인
    case state.profile_state do
      :idle ->
        # 프로필 완전한지 확인
        case check_and_start_profile_collection(state) do
          {:collecting, new_state, greeting} ->
            # 사용자 메시지 저장
            save_message(state.conversation_id, %{
              role: :user,
              content: user_message,
              agent_id: nil
            })

            # 인사말 + 첫 질문 저장
            save_message(state.conversation_id, %{
              role: :assistant,
              content: greeting,
              agent_id: state.agent_id
            })

            {:reply, {:ok, greeting}, new_state}

          {:complete, _state} ->
            # 프로필 완료, 정상 처리
            process_normal_message(state, user_message)
        end

      collecting_state
      when collecting_state in [:collecting_user_name, :collecting_agent_name, :collecting_city] ->
        # 프로필 수집 중 - 응답 처리
        process_profile_response(state, user_message)

      :complete ->
        # 프로필 수집 완료, 정상 처리
        process_normal_message(state, user_message)
    end
  end

  @impl true
  def handle_call({:stream_chat, user_message, liveview_pid}, _from, state) do
    Logger.info("SupervisorAgent received streaming message: #{user_message}")

    # 프로필 수집 중인 경우 일반 응답 (짧은 응답이므로 스트리밍 불필요)
    case state.profile_state do
      :idle ->
        case check_and_start_profile_collection(state) do
          {:collecting, new_state, greeting} ->
            save_message(state.conversation_id, %{
              role: :user,
              content: user_message,
              agent_id: nil
            })

            save_message(state.conversation_id, %{
              role: :assistant,
              content: greeting,
              agent_id: state.agent_id
            })

            {:reply, {:ok, greeting}, new_state}

          {:complete, _state} ->
            process_streaming_message(state, user_message, liveview_pid)
        end

      collecting_state
      when collecting_state in [:collecting_user_name, :collecting_agent_name, :collecting_city] ->
        # 프로필 수집 중 - 일반 응답 처리
        process_profile_response(state, user_message)

      :complete ->
        # 프로필 수집 완료, 스트리밍 처리
        process_streaming_message(state, user_message, liveview_pid)
    end
  end

  # 프로필 완료 여부 확인 및 수집 시작
  defp check_and_start_profile_collection(state) do
    case MemoryManager.get_user_profile() do
      {:ok, profile} ->
        user_name = Map.get(profile, "user_name") || Map.get(profile, :user_name)
        agent_name = Map.get(profile, "agent_name") || Map.get(profile, :agent_name)
        city = Map.get(profile, "city") || Map.get(profile, :city)

        cond do
          !user_name ->
            greeting = """
            안녕하세요! 👋 저는 당신의 AI 비서입니다.

            더 나은 서비스를 제공하기 위해 몇 가지 정보를 알고 싶어요.

            먼저, **어떻게 불러드리면 될까요?** 이름이나 별명을 알려주세요.
            """

            {:collecting,
             %{state | profile_state: :collecting_user_name, partial_profile: profile}, greeting}

          !agent_name ->
            greeting = """
            #{user_name}님, 반가워요! 😊

            저에게도 이름을 지어주실 수 있나요? **저를 뭐라고 부르고 싶으세요?**
            (예: 아리, 제이, 클로버 등)
            """

            {:collecting,
             %{state | profile_state: :collecting_agent_name, partial_profile: profile}, greeting}

          !city ->
            greeting = """
            좋아요, #{user_name}님! 저는 이제 #{agent_name}(이)에요. 🎉

            마지막으로, **현재 어느 도시에 계신가요?**
            날씨나 시간 등 맞춤 정보를 제공하는 데 도움이 됩니다.
            """

            {:collecting, %{state | profile_state: :collecting_city, partial_profile: profile},
             greeting}

          true ->
            {:complete, %{state | profile_state: :complete}}
        end

      {:error, _} ->
        # 프로필 없음 - 처음부터 시작
        greeting = """
        안녕하세요! 👋 저는 당신의 AI 비서입니다.

        더 나은 서비스를 제공하기 위해 몇 가지 정보를 알고 싶어요.

        먼저, **어떻게 불러드리면 될까요?** 이름이나 별명을 알려주세요.
        """

        {:collecting, %{state | profile_state: :collecting_user_name, partial_profile: %{}},
         greeting}
    end
  end

  # 프로필 응답 처리
  defp process_profile_response(state, user_message) do
    # 사용자 메시지 저장
    save_message(state.conversation_id, %{
      role: :user,
      content: user_message,
      agent_id: nil
    })

    trimmed_input = String.trim(user_message)

    case state.profile_state do
      :collecting_user_name ->
        # 사용자 이름 저장
        new_profile = Map.put(state.partial_profile, :user_name, trimmed_input)
        save_partial_profile(new_profile)

        response = """
        #{trimmed_input}님, 반가워요! 😊

        저에게도 이름을 지어주실 수 있나요? **저를 뭐라고 부르고 싶으세요?**
        (예: 아리, 제이, 클로버 등)
        """

        save_message(state.conversation_id, %{
          role: :assistant,
          content: response,
          agent_id: state.agent_id
        })

        new_state = %{state | profile_state: :collecting_agent_name, partial_profile: new_profile}
        {:reply, {:ok, response}, new_state}

      :collecting_agent_name ->
        # AI 비서 이름 저장
        user_name =
          Map.get(state.partial_profile, :user_name) ||
            Map.get(state.partial_profile, "user_name")

        new_profile = Map.put(state.partial_profile, :agent_name, trimmed_input)
        save_partial_profile(new_profile)

        response = """
        좋아요, #{user_name}님! 저는 이제 #{trimmed_input}(이)에요. 🎉

        마지막으로, **현재 어느 도시에 계신가요?**
        날씨나 시간 등 맞춤 정보를 제공하는 데 도움이 됩니다.
        """

        save_message(state.conversation_id, %{
          role: :assistant,
          content: response,
          agent_id: state.agent_id
        })

        new_state = %{state | profile_state: :collecting_city, partial_profile: new_profile}
        {:reply, {:ok, response}, new_state}

      :collecting_city ->
        # 도시 저장 및 프로필 완료
        user_name =
          Map.get(state.partial_profile, :user_name) ||
            Map.get(state.partial_profile, "user_name")

        agent_name =
          Map.get(state.partial_profile, :agent_name) ||
            Map.get(state.partial_profile, "agent_name")

        new_profile = Map.put(state.partial_profile, :city, trimmed_input)

        # 완전한 프로필 저장
        case MemoryManager.save_user_profile(new_profile) do
          {:ok, _} ->
            Logger.info("Profile collection completed for user: #{user_name}")

          {:error, reason} ->
            Logger.warning("Failed to save profile: #{inspect(reason)}")
        end

        response = """
        완벽해요! 🎊

        **#{user_name}**님, #{trimmed_input}에서 만나뵙게 되어 기쁩니다!
        저 **#{agent_name}**(이)가 앞으로 최선을 다해 도와드릴게요.

        무엇이든 물어보세요! 계산, 웹 검색, 날씨 등 다양한 도움을 드릴 수 있어요. 😄
        """

        save_message(state.conversation_id, %{
          role: :assistant,
          content: response,
          agent_id: state.agent_id
        })

        new_state = %{state | profile_state: :complete, partial_profile: new_profile}
        {:reply, {:ok, response}, new_state}
    end
  end

  # 부분 프로필 저장 (MemoryManager 활용)
  defp save_partial_profile(profile) do
    # 임시로 부분 프로필도 저장 (빈 값이 있어도)
    MemoryManager.save_user_profile(profile)
  end

  # 스트리밍 메시지 처리
  defp process_streaming_message(state, user_message, liveview_pid) do
    start_time = System.monotonic_time(:millisecond)

    # 사용자 메시지 저장
    save_message(state.conversation_id, %{
      role: :user,
      content: user_message,
      agent_id: nil
    })

    # Worker에게 스트리밍 작업 위임
    case delegate_to_worker_stream(state, user_message, liveview_pid) do
      {:ok, result, worker_name} ->
        duration_ms = System.monotonic_time(:millisecond) - start_time

        # 어시스턴트 메시지 저장
        save_message(state.conversation_id, %{
          role: :assistant,
          content: result,
          agent_id: state.agent_id
        })

        # 성능 메트릭 기록
        record_performance_metric(state, worker_name, duration_ms, true)

        # LiveView에 완료 알림 (최종 응답 포함)
        send(liveview_pid, {:stream_complete, state.conversation_id, result})

        {:reply, {:ok, result}, state}

      {:error, reason} = error ->
        duration_ms = System.monotonic_time(:millisecond) - start_time

        # 오류 메시지 저장
        error_message = "작업 수행 중 오류가 발생했습니다: #{inspect(reason)}"

        save_message(state.conversation_id, %{
          role: :assistant,
          content: error_message,
          agent_id: state.agent_id
        })

        # 실패 메트릭 기록
        record_performance_metric(state, "unknown", duration_ms, false)

        # 학습을 위한 오류 패턴 기록
        record_error_pattern(state, user_message, reason)

        {:reply, error, state}
    end
  end

  # 일반 메시지 처리 (기존 로직)
  defp process_normal_message(state, user_message) do
    start_time = System.monotonic_time(:millisecond)

    # 사용자 메시지 저장
    save_message(state.conversation_id, %{
      role: :user,
      content: user_message,
      agent_id: nil
    })

    # Worker에게 작업 위임
    case delegate_to_worker(state, user_message) do
      {:ok, result, worker_name} ->
        duration_ms = System.monotonic_time(:millisecond) - start_time

        # 어시스턴트 메시지 저장
        save_message(state.conversation_id, %{
          role: :assistant,
          content: result,
          agent_id: state.agent_id
        })

        # 성능 메트릭 기록
        record_performance_metric(state, worker_name, duration_ms, true)

        {:reply, {:ok, result}, state}

      {:error, reason} = error ->
        duration_ms = System.monotonic_time(:millisecond) - start_time

        # 오류 메시지 저장
        error_message = "작업 수행 중 오류가 발생했습니다: #{inspect(reason)}"

        save_message(state.conversation_id, %{
          role: :assistant,
          content: error_message,
          agent_id: state.agent_id
        })

        # 실패 메트릭 기록
        record_performance_metric(state, "unknown", duration_ms, false)

        # 학습을 위한 오류 패턴 기록
        record_error_pattern(state, user_message, reason)

        {:reply, error, state}
    end
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("SupervisorAgent terminating: #{inspect(reason)}")

    # 대화 요약 저장
    save_conversation_summary(state)

    # 메모리를 Markdown 파일로 내보내기
    export_memory_to_markdown(state.agent_id)

    # 모든 Worker 프로세스 종료
    Enum.each(state.worker_agents, fn {_agent, pid} ->
      if Process.alive?(pid) do
        Process.exit(pid, :shutdown)
      end
    end)

    :ok
  end

  # 비공개 함수들

  defp via_tuple(conversation_id) do
    {:via, Registry, {Core.Agent.Registry, {:supervisor, conversation_id}}}
  end

  defp start_workers(worker_agents_data) do
    Enum.map(worker_agents_data, fn agent ->
      case WorkerAgent.start_link(agent_id: agent.id) do
        {:ok, pid} ->
          {agent, pid}

        {:error, reason} ->
          Logger.error("Failed to start worker #{agent.name}: #{inspect(reason)}")
          {agent, nil}
      end
    end)
    |> Enum.filter(fn {_agent, pid} -> pid != nil end)
  end

  # 프로필 상태 초기화
  defp init_profile_state do
    case MemoryManager.get_user_profile() do
      {:ok, profile} ->
        user_name = Map.get(profile, "user_name") || Map.get(profile, :user_name)
        agent_name = Map.get(profile, "agent_name") || Map.get(profile, :agent_name)
        city = Map.get(profile, "city") || Map.get(profile, :city)

        if user_name && agent_name && city do
          {:complete, profile}
        else
          {:idle, profile}
        end

      {:error, _} ->
        {:idle, %{}}
    end
  end

  # 스트리밍 모드로 Worker에게 작업 위임
  defp delegate_to_worker_stream(state, user_request, liveview_pid) do
    # 후처리 Worker 제외한 핵심 Worker만 필터링
    postprocess_workers = ["restructure_worker", "emoji_worker"]

    available_workers =
      state.worker_agents
      |> Enum.map(fn {agent, _pid} -> agent end)
      |> Enum.reject(fn agent -> agent.name in postprocess_workers end)

    # 1단계: 핵심 Worker 선택 및 스트리밍 실행
    case TaskRouter.select_worker(user_request, available_workers) do
      {:ok, selected_worker} ->
        Logger.info("[Streaming Pipeline] Selected primary worker: #{selected_worker.name}")

        # 스트리밍 콜백 생성 - LiveView에 청크 전송
        stream_callback = fn
          {:chunk, text} ->
            send(liveview_pid, {:stream_chunk, state.conversation_id, text})

          {:tool_execution, tool_calls} ->
            tool_names = Enum.map(tool_calls, fn tc -> tc["function"]["name"] end)
            send(liveview_pid, {:stream_tool_start, state.conversation_id, tool_names})

          {:tool_completed, _tool_calls} ->
            send(liveview_pid, {:stream_tool_end, state.conversation_id})

          {:finish, _reason} ->
            send(liveview_pid, {:stream_finish, state.conversation_id})

          _ ->
            :ok
        end

        case execute_worker_by_agent_stream(
               state,
               selected_worker,
               user_request,
               nil,
               stream_callback
             ) do
          {:ok, primary_result} ->
            Logger.info("[Streaming Pipeline] Primary worker completed")

            # 후처리는 비스트리밍으로 처리 (짧은 응답)
            # 스트리밍 완료 알림
            send(liveview_pid, {:stream_postprocess, state.conversation_id})

            # 2단계: restructure_worker로 구조 재편
            case execute_postprocess_worker(state, "restructure_worker", primary_result) do
              {:ok, restructured_result} ->
                Logger.info("[Pipeline 2/3] Restructure worker completed")

                # 3단계: emoji_worker로 스타일 개선
                case execute_postprocess_worker(state, "emoji_worker", restructured_result) do
                  {:ok, final_result} ->
                    Logger.info("[Pipeline 3/3] Emoji worker completed")
                    {:ok, final_result, selected_worker.name}

                  {:error, :worker_not_found} ->
                    {:ok, restructured_result, selected_worker.name}

                  {:error, _reason} ->
                    {:ok, restructured_result, selected_worker.name}
                end

              {:error, :worker_not_found} ->
                {:ok, primary_result, selected_worker.name}

              {:error, _reason} ->
                {:ok, primary_result, selected_worker.name}
            end

          {:error, reason} ->
            {:error, reason}
        end

      {:error, :no_workers_available} = error ->
        Logger.error("No workers available for streaming")
        error
    end
  end

  defp delegate_to_worker(state, user_request) do
    # 3단계 파이프라인 실행:
    # 1단계: 핵심 Worker 선택 및 실행 (calculator, general 등)
    # 2단계: restructure_worker로 구조 재편
    # 3단계: emoji_worker로 스타일 개선

    # 후처리 Worker 제외한 핵심 Worker만 필터링
    postprocess_workers = ["restructure_worker", "emoji_worker"]

    available_workers =
      state.worker_agents
      |> Enum.map(fn {agent, _pid} -> agent end)
      |> Enum.reject(fn agent -> agent.name in postprocess_workers end)

    # 1단계: 핵심 Worker 선택 및 실행
    case TaskRouter.select_worker(user_request, available_workers) do
      {:ok, selected_worker} ->
        Logger.info("[Pipeline 1/3] Selected primary worker: #{selected_worker.name}")

        case execute_worker_by_agent(state, selected_worker, user_request, nil) do
          {:ok, primary_result} ->
            Logger.info("[Pipeline 1/3] Primary worker completed")

            # 2단계: restructure_worker로 구조 재편
            case execute_postprocess_worker(state, "restructure_worker", primary_result) do
              {:ok, restructured_result} ->
                Logger.info("[Pipeline 2/3] Restructure worker completed")

                # 3단계: emoji_worker로 스타일 개선
                case execute_postprocess_worker(state, "emoji_worker", restructured_result) do
                  {:ok, final_result} ->
                    Logger.info("[Pipeline 3/3] Emoji worker completed - Pipeline finished")
                    {:ok, final_result, selected_worker.name}

                  {:error, :worker_not_found} ->
                    Logger.warning(
                      "[Pipeline 3/3] emoji_worker not found, using restructured result"
                    )

                    {:ok, restructured_result, selected_worker.name}

                  {:error, reason} ->
                    Logger.warning(
                      "[Pipeline 3/3] emoji_worker failed: #{inspect(reason)}, using restructured result"
                    )

                    {:ok, restructured_result, selected_worker.name}
                end

              {:error, :worker_not_found} ->
                Logger.warning(
                  "[Pipeline 2/3] restructure_worker not found, using primary result"
                )

                {:ok, primary_result, selected_worker.name}

              {:error, reason} ->
                Logger.warning(
                  "[Pipeline 2/3] restructure_worker failed: #{inspect(reason)}, using primary result"
                )

                {:ok, primary_result, selected_worker.name}
            end

          {:error, reason} ->
            {:error, reason}
        end

      {:error, :no_workers_available} = error ->
        Logger.error("No workers available")
        error
    end
  end

  # 특정 Agent 구조체로 Worker 실행
  defp execute_worker_by_agent(state, agent, user_request, context) do
    case find_worker_pid(state, agent.id) do
      {:ok, worker_pid} ->
        task_attrs = %{
          conversation_id: state.conversation_id,
          supervisor_id: state.agent_id,
          user_request: user_request,
          context: context
        }

        Coordinator.send_task(state.agent_id, agent.id, worker_pid, task_attrs)

      {:error, _} = error ->
        error
    end
  end

  # 특정 Agent 구조체로 Worker 스트리밍 실행
  defp execute_worker_by_agent_stream(state, agent, user_request, context, stream_callback) do
    case find_worker_pid(state, agent.id) do
      {:ok, worker_pid} ->
        task_attrs = %{
          conversation_id: state.conversation_id,
          supervisor_id: state.agent_id,
          user_request: user_request,
          context: context
        }

        Coordinator.send_task_stream(
          state.agent_id,
          agent.id,
          worker_pid,
          task_attrs,
          stream_callback
        )

      {:error, _} = error ->
        error
    end
  end

  # 이름으로 후처리 Worker 실행 (이전 단계 결과를 context로 전달)
  defp execute_postprocess_worker(state, worker_name, previous_result) do
    case find_worker_by_name(state, worker_name) do
      {:ok, agent, worker_pid} ->
        # 후처리 Worker에게는 이전 결과를 user_request로 전달
        # (텍스트 변환이 주 목적이므로)
        task_attrs = %{
          conversation_id: state.conversation_id,
          supervisor_id: state.agent_id,
          user_request: previous_result,
          context: "이전 단계의 결과를 처리해주세요."
        }

        Coordinator.send_task(state.agent_id, agent.id, worker_pid, task_attrs)

      {:error, _} = error ->
        error
    end
  end

  defp find_worker_pid(state, agent_id) do
    case Enum.find(state.worker_agents, fn {agent, _pid} -> agent.id == agent_id end) do
      {_agent, pid} -> {:ok, pid}
      nil -> {:error, :worker_not_found}
    end
  end

  defp find_worker_by_name(state, worker_name) do
    case Enum.find(state.worker_agents, fn {agent, _pid} -> agent.name == worker_name end) do
      {agent, pid} -> {:ok, agent, pid}
      nil -> {:error, :worker_not_found}
    end
  end

  defp save_message(conversation_id, attrs) do
    attrs_with_conv = Map.put(attrs, :conversation_id, conversation_id)

    %Message{}
    |> Message.changeset(attrs_with_conv)
    |> Repo.insert()
  end

  defp record_performance_metric(state, worker_name, duration_ms, success) do
    # 타임스탬프 기반 고유 키 생성
    key = "task_#{DateTime.utc_now() |> DateTime.to_unix()}"

    value = %{
      worker_used: worker_name,
      duration_ms: duration_ms,
      success: success,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    opts = [
      conversation_id: state.conversation_id,
      relevance_score: 0.5
    ]

    case MemoryManager.store(state.agent_id, :performance_metric, key, value, opts) do
      {:ok, _memory} ->
        Logger.debug("Recorded performance metric: #{worker_name} (#{duration_ms}ms, #{success})")

      {:error, reason} ->
        Logger.warning("Failed to record performance metric: #{inspect(reason)}")
    end
  end

  defp record_error_pattern(state, user_request, error_reason) do
    # 오류에서 간단한 키 생성
    error_type = inspect(error_reason) |> String.slice(0, 50)
    key = "error_#{:erlang.phash2(error_type)}"

    value = %{
      user_request: user_request,
      error: inspect(error_reason),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      frequency: 1
    }

    # 이 오류 패턴이 이미 존재하는지 확인
    existing = MemoryManager.retrieve(state.agent_id, :learned_pattern, key: key)

    value =
      case existing do
        [memory | _] ->
          # 빈도 증가
          old_value = memory.value
          %{value | frequency: Map.get(old_value, "frequency", 1) + 1}

        [] ->
          value
      end

    opts = [
      conversation_id: state.conversation_id,
      relevance_score: 0.7
    ]

    case MemoryManager.store(state.agent_id, :learned_pattern, key, value, opts) do
      {:ok, _memory} ->
        Logger.debug("Recorded error pattern: #{key}")

      {:error, reason} ->
        Logger.warning("Failed to record error pattern: #{inspect(reason)}")
    end
  end

  # Markdown 파일에서 메모리 로드
  defp load_memory_from_markdown(agent_id, agent_name) do
    memory_path = Path.join(["data/memories", agent_name, "memory.md"])

    if File.exists?(memory_path) do
      case MemoryManager.import_from_markdown(agent_id, memory_path) do
        {:ok, memories} ->
          Logger.info("Loaded #{length(memories)} memories from #{memory_path}")

        {:error, reason} ->
          Logger.warning("Failed to load memories from markdown: #{inspect(reason)}")
      end
    else
      Logger.debug("No memory file found at #{memory_path}, starting fresh")
    end
  end

  # 메모리를 Markdown 파일로 저장
  defp export_memory_to_markdown(agent_id) do
    case MemoryManager.export_to_markdown(agent_id) do
      {:ok, path} ->
        Logger.info("Exported memories to #{path}")

      {:error, reason} ->
        Logger.warning("Failed to export memories to markdown: #{inspect(reason)}")
    end
  end

  # 대화 요약 저장
  defp save_conversation_summary(state) do
    # 대화에서 메시지 가져오기
    messages = get_conversation_messages(state.conversation_id)

    if length(messages) > 0 do
      summary = generate_conversation_summary(messages)

      key = "conversation_#{state.conversation_id}"

      opts = [
        conversation_id: state.conversation_id,
        relevance_score: 0.8
      ]

      case MemoryManager.store(state.agent_id, :conversation_summary, key, summary, opts) do
        {:ok, _memory} ->
          Logger.debug("Saved conversation summary for #{state.conversation_id}")

        {:error, reason} ->
          Logger.warning("Failed to save conversation summary: #{inspect(reason)}")
      end
    end
  end

  # 대화 메시지 조회
  defp get_conversation_messages(conversation_id) do
    import Ecto.Query

    from(m in Message,
      where: m.conversation_id == ^conversation_id,
      order_by: [asc: m.inserted_at]
    )
    |> Repo.all()
  end

  # 대화 요약 생성
  defp generate_conversation_summary(messages) do
    user_messages =
      messages
      |> Enum.filter(fn m -> m.role == :user end)
      |> Enum.map(fn m -> m.content end)

    assistant_messages =
      messages
      |> Enum.filter(fn m -> m.role == :assistant end)
      |> Enum.map(fn m -> m.content end)

    %{
      total_messages: length(messages),
      user_message_count: length(user_messages),
      assistant_message_count: length(assistant_messages),
      topics: extract_topics(user_messages),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  # 주요 토픽 추출 (간단한 구현)
  defp extract_topics(user_messages) do
    user_messages
    |> Enum.take(5)
    |> Enum.map(fn msg -> String.slice(msg, 0, 50) end)
  end
end
