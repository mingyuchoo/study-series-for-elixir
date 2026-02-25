defmodule Core.Agent.WorkerAgent do
  @moduledoc """
  Worker 에이전트 GenServer.

  Supervisor로부터 작업을 받아 실행하고 결과를 반환합니다.
  Agent 테이블의 설정을 기반으로 동작하며, enabled_tools만 사용합니다.
  """

  use GenServer
  require Logger

  alias Core.Agent.{MemoryManager, ReactEngine, ToolRegistry, SkillRegistry}
  alias Core.Contexts.Agents
  alias Core.Schema.{Agent, AgentTask}
  alias Core.Repo

  defstruct [:agent_id, :agent, :tools, :current_task]

  # 클라이언트 API

  @doc """
  WorkerAgent 프로세스를 시작합니다.

  ## Options

    - `:agent_id` - Agent 테이블의 에이전트 ID (필수)
  """
  def start_link(opts) do
    agent_id = Keyword.fetch!(opts, :agent_id)
    GenServer.start_link(__MODULE__, agent_id)
  end

  @doc """
  Worker에게 작업을 실행하도록 요청합니다.

  ## Parameters

    - `worker_pid` - Worker 프로세스 PID
    - `task_attrs` - 작업 정보
      - `:conversation_id` - 대화 ID
      - `:user_request` - 사용자 요청
      - `:context` - 추가 컨텍스트 (선택)

  ## Returns

    - `{:ok, result}` - 성공 시 작업 결과
    - `{:error, reason}` - 실패 시 오류 원인
  """
  def execute_task(worker_pid, task_attrs) do
    GenServer.call(worker_pid, {:execute_task, task_attrs}, 120_000)
  end

  @doc """
  Worker에게 스트리밍 모드로 작업을 실행하도록 요청합니다.

  ## Parameters

    - `worker_pid` - Worker 프로세스 PID
    - `task_attrs` - 작업 정보
    - `stream_callback` - 스트리밍 청크 콜백 함수

  ## Returns

    - `{:ok, result}` - 성공 시 최종 결과
    - `{:error, reason}` - 실패 시 오류 원인
  """
  def execute_task_stream(worker_pid, task_attrs, stream_callback) do
    GenServer.call(worker_pid, {:execute_task_stream, task_attrs, stream_callback}, 180_000)
  end

  # 서버 콜백

  @impl true
  def init(agent_id) do
    case Agents.get_agent(agent_id) do
      nil ->
        {:stop, {:error, :agent_not_found}}

      %Agent{type: :worker} = agent ->
        tools = load_enabled_tools(agent)

        state = %__MODULE__{
          agent_id: agent_id,
          agent: agent,
          tools: tools,
          current_task: nil
        }

        Logger.info("WorkerAgent started: #{agent.name} (#{agent_id})")
        {:ok, state}

      %Agent{type: type} ->
        {:stop, {:error, {:invalid_agent_type, type}}}
    end
  end

  @impl true
  def handle_call({:execute_task, task_attrs}, _from, state) do
    Logger.info("WorkerAgent #{state.agent.name} received task: #{inspect(task_attrs)}")

    # AgentTask 레코드 생성
    {:ok, agent_task} = create_agent_task(state, task_attrs)
    state = %{state | current_task: agent_task}

    # 작업 상태를 진행 중으로 업데이트
    {:ok, agent_task} =
      agent_task
      |> AgentTask.changeset(%{status: :in_progress, started_at: DateTime.utc_now()})
      |> Repo.update()

    start_time = System.monotonic_time(:millisecond)

    # ReactEngine을 사용하여 작업 실행
    case run_task(state, task_attrs) do
      {:ok, result} ->
        duration_ms = System.monotonic_time(:millisecond) - start_time

        # 작업 상태를 완료로 업데이트
        {:ok, _agent_task} = update_task_status(agent_task, :completed, result)

        # 성공 작업 학습 (메모리 저장)
        record_task_execution(state, task_attrs, result, duration_ms, true)

        state = %{state | current_task: nil}
        {:reply, {:ok, result}, state}

      {:error, reason} = error ->
        duration_ms = System.monotonic_time(:millisecond) - start_time

        # 작업 상태를 실패로 업데이트
        {:ok, _agent_task} = update_task_status(agent_task, :failed, reason)

        # 실패 패턴 학습 (메모리 저장)
        record_task_execution(state, task_attrs, reason, duration_ms, false)

        state = %{state | current_task: nil}
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:execute_task_stream, task_attrs, stream_callback}, _from, state) do
    Logger.info("WorkerAgent #{state.agent.name} received streaming task: #{inspect(task_attrs)}")

    # AgentTask 레코드 생성
    {:ok, agent_task} = create_agent_task(state, task_attrs)
    state = %{state | current_task: agent_task}

    # 작업 상태를 진행 중으로 업데이트
    {:ok, agent_task} =
      agent_task
      |> AgentTask.changeset(%{status: :in_progress, started_at: DateTime.utc_now()})
      |> Repo.update()

    start_time = System.monotonic_time(:millisecond)

    # ReactEngine 스트리밍 모드로 실행
    case run_task_stream(state, task_attrs, stream_callback) do
      {:ok, result} ->
        duration_ms = System.monotonic_time(:millisecond) - start_time

        # 작업 상태를 완료로 업데이트
        {:ok, _agent_task} = update_task_status(agent_task, :completed, result)

        # 성공 작업 학습 (메모리 저장)
        record_task_execution(state, task_attrs, result, duration_ms, true)

        state = %{state | current_task: nil}
        {:reply, {:ok, result}, state}

      {:error, reason} = error ->
        duration_ms = System.monotonic_time(:millisecond) - start_time

        # 작업 상태를 실패로 업데이트
        {:ok, _agent_task} = update_task_status(agent_task, :failed, reason)

        # 실패 패턴 학습 (메모리 저장)
        record_task_execution(state, task_attrs, reason, duration_ms, false)

        state = %{state | current_task: nil}
        {:reply, error, state}
    end
  end

  # 비공개 함수들

  defp load_enabled_tools(%Agent{enabled_tools: enabled_tool_names}) do
    all_tools = ToolRegistry.get_tools()

    Enum.filter(all_tools, fn tool ->
      tool.name in enabled_tool_names
    end)
  end

  defp create_agent_task(state, task_attrs) do
    attrs = %{
      conversation_id: task_attrs[:conversation_id],
      supervisor_id: task_attrs[:supervisor_id],
      worker_id: state.agent_id,
      task_type: "execute",
      status: :pending,
      input_data: %{
        user_request: task_attrs[:user_request],
        context: task_attrs[:context]
      }
    }

    %AgentTask{}
    |> AgentTask.changeset(attrs)
    |> Repo.insert()
  end

  defp update_task_status(task, :completed, result) do
    attrs = %{
      status: :completed,
      output_data: %{result: result},
      completed_at: DateTime.utc_now()
    }

    task
    |> AgentTask.changeset(attrs)
    |> Repo.update()
  end

  defp update_task_status(task, :failed, error) do
    attrs = %{
      status: :failed,
      error_message: inspect(error),
      completed_at: DateTime.utc_now()
    }

    task
    |> AgentTask.changeset(attrs)
    |> Repo.update()
  end

  defp update_task_status(task, status, _extra) do
    attrs = %{status: status}

    task
    |> AgentTask.changeset(attrs)
    |> Repo.update()
  end

  defp run_task(state, task_attrs) do
    user_request = task_attrs[:user_request]
    context = task_attrs[:context]

    # 초기 메시지 구성
    messages = build_initial_messages(user_request, context)

    # 스킬이 포함된 시스템 프롬프트 구성
    system_prompt = build_system_prompt_with_skills(state.agent)

    # ReactEngine 실행
    opts = [
      system_prompt: system_prompt,
      max_iterations: state.agent.max_iterations || 10
    ]

    case ReactEngine.run(messages, state.tools, opts) do
      {:ok, result, _final_messages} ->
        {:ok, result}

      {:error, reason} ->
        Logger.error("Task execution failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp run_task_stream(state, task_attrs, stream_callback) do
    user_request = task_attrs[:user_request]
    context = task_attrs[:context]

    # 초기 메시지 구성
    messages = build_initial_messages(user_request, context)

    # 스킬이 포함된 시스템 프롬프트 구성
    system_prompt = build_system_prompt_with_skills(state.agent)

    # ReactEngine 스트리밍 모드 실행
    opts = [
      system_prompt: system_prompt,
      max_iterations: state.agent.max_iterations || 10
    ]

    case ReactEngine.run_stream(messages, state.tools, stream_callback, opts) do
      {:ok, result, _final_messages} ->
        {:ok, result}

      {:error, reason} ->
        Logger.error("Streaming task execution failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_system_prompt_with_skills(agent) do
    # 에이전트의 활성화된 도구 기반으로 사용 가능한 스킬 가져오기
    available_skills = SkillRegistry.get_available_skills(agent.enabled_tools)

    # 스킬 프롬프트 섹션 구성
    skill_prompt = SkillRegistry.build_skill_prompt(available_skills)

    # 사용자 프로필 정보 가져오기
    user_context = build_user_context()

    # 기본 시스템 프롬프트에 사용자 컨텍스트와 스킬 지식 결합
    base_prompt =
      if user_context != "" do
        """
        #{user_context}

        #{agent.system_prompt}
        """
      else
        agent.system_prompt
      end

    if skill_prompt == "" do
      base_prompt
    else
      """
      #{base_prompt}

      ---

      #{skill_prompt}
      """
    end
  end

  # 사용자 프로필 기반 컨텍스트 생성
  defp build_user_context do
    case MemoryManager.get_user_profile() do
      {:ok, profile} ->
        user_name = Map.get(profile, "user_name") || Map.get(profile, :user_name)
        agent_name = Map.get(profile, "agent_name") || Map.get(profile, :agent_name)
        city = Map.get(profile, "city") || Map.get(profile, :city)

        if user_name && agent_name && city do
          """
          [사용자 정보]
          - 사용자 이름: #{user_name}
          - 당신의 이름: #{agent_name}
          - 사용자 위치: #{city}

          위 정보를 활용하여 개인화된 응답을 제공하세요. 사용자를 이름으로 부르고, 위치 기반 정보(날씨, 시간 등)를 제공할 때 활용하세요.
          """
        else
          ""
        end

      {:error, _} ->
        ""
    end
  end

  defp build_initial_messages(user_request, context) do
    messages = []

    messages =
      if context do
        [
          %{
            role: "system",
            content: "Additional context: #{context}",
            tool_calls: nil,
            tool_call_id: nil
          }
          | messages
        ]
      else
        messages
      end

    messages ++
      [
        %{
          role: "user",
          content: user_request,
          tool_calls: nil,
          tool_call_id: nil
        }
      ]
  end

  # 작업 실행 결과를 메모리에 저장
  defp record_task_execution(state, task_attrs, result_or_error, duration_ms, success) do
    key = "task_#{DateTime.utc_now() |> DateTime.to_unix()}"

    value = %{
      worker_name: state.agent.name,
      user_request: task_attrs[:user_request] |> String.slice(0, 200),
      duration_ms: duration_ms,
      success: success,
      result_preview:
        if success do
          result_or_error |> String.slice(0, 100)
        else
          inspect(result_or_error) |> String.slice(0, 100)
        end,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    opts = [
      conversation_id: task_attrs[:conversation_id],
      relevance_score: if(success, do: 0.5, else: 0.7)
    ]

    memory_type = if success, do: :performance_metric, else: :learned_pattern

    case MemoryManager.store(state.agent_id, memory_type, key, value, opts) do
      {:ok, _memory} ->
        Logger.debug("Worker #{state.agent.name} recorded #{memory_type}: #{success}")

      {:error, reason} ->
        Logger.warning("Failed to record worker memory: #{inspect(reason)}")
    end
  end
end
