defmodule Core.Agent.Coordinator do
  @moduledoc """
  Supervisor와 Worker 간 작업 전달 및 통신을 조정합니다.

  - 작업 전달 (Supervisor → Worker)
  - 작업 상태 추적
  - 에이전트 간 상호작용 기록
  """

  require Logger

  alias Core.Agent.WorkerAgent
  alias Core.Schema.{AgentTask, AgentInteraction}
  alias Core.Repo
  import Ecto.Query

  @doc """
  Worker에게 작업을 전달합니다.

  ## Parameters

    - `supervisor_id` - Supervisor 에이전트 ID
    - `worker_id` - Worker 에이전트 ID
    - `worker_pid` - Worker 프로세스 PID
    - `task_attrs` - 작업 정보
      - `:conversation_id` - 대화 ID
      - `:user_request` - 사용자 요청
      - `:context` - 추가 컨텍스트 (선택)

  ## Returns

    - `{:ok, result}` - 성공 시 작업 결과
    - `{:error, reason}` - 실패 시 오류 원인

  ## Examples

      iex> Coordinator.send_task(supervisor_id, worker_id, worker_pid, %{
      ...>   conversation_id: conv_id,
      ...>   user_request: "2 + 2를 계산해줘"
      ...> })
      {:ok, "4입니다."}
  """
  def send_task(supervisor_id, worker_id, worker_pid, task_attrs) do
    conversation_id = task_attrs[:conversation_id]
    user_request = task_attrs[:user_request]

    Logger.info("Coordinator: Supervisor #{supervisor_id} sending task to Worker #{worker_id}")

    # 상호작용 기록 - 작업 위임
    {:ok, interaction} =
      create_interaction(supervisor_id, worker_id, conversation_id, :task_delegation, %{
        user_request: user_request
      })

    # Worker에서 작업 실행
    case WorkerAgent.execute_task(worker_pid, task_attrs) do
      {:ok, result} ->
        # 상호작용 내용에 결과 추가 (작업 위임 타입 유지)
        add_result_to_interaction(interaction, %{
          status: "completed",
          result: result
        })

        {:ok, result}

      {:error, reason} = error ->
        # 상호작용 내용에 오류 추가 (작업 위임 타입 유지)
        add_result_to_interaction(interaction, %{
          status: "failed",
          error: inspect(reason)
        })

        error
    end
  end

  @doc """
  Worker에게 스트리밍 모드로 작업을 전달합니다.

  ## Parameters

    - `supervisor_id` - Supervisor 에이전트 ID
    - `worker_id` - Worker 에이전트 ID
    - `worker_pid` - Worker 프로세스 PID
    - `task_attrs` - 작업 정보
    - `stream_callback` - 스트리밍 청크 콜백 함수

  ## Returns

    - `{:ok, result}` - 성공 시 최종 결과
    - `{:error, reason}` - 실패 시 오류 원인
  """
  def send_task_stream(supervisor_id, worker_id, worker_pid, task_attrs, stream_callback) do
    conversation_id = task_attrs[:conversation_id]
    user_request = task_attrs[:user_request]

    Logger.info(
      "Coordinator: Supervisor #{supervisor_id} sending streaming task to Worker #{worker_id}"
    )

    # 상호작용 기록 - 작업 위임
    {:ok, interaction} =
      create_interaction(supervisor_id, worker_id, conversation_id, :task_delegation, %{
        user_request: user_request,
        streaming: true
      })

    # Worker에서 스트리밍 작업 실행
    case WorkerAgent.execute_task_stream(worker_pid, task_attrs, stream_callback) do
      {:ok, result} ->
        # 상호작용 내용에 결과 추가
        add_result_to_interaction(interaction, %{
          status: "completed",
          result: result
        })

        {:ok, result}

      {:error, reason} = error ->
        # 상호작용 내용에 오류 추가
        add_result_to_interaction(interaction, %{
          status: "failed",
          error: inspect(reason)
        })

        error
    end
  end

  @doc """
  특정 대화의 모든 작업을 조회합니다.

  ## Examples

      iex> Coordinator.list_tasks(conversation_id)
      [%AgentTask{}, ...]
  """
  def list_tasks(conversation_id) do
    AgentTask
    |> where([t], t.conversation_id == ^conversation_id)
    |> order_by([t], desc: t.inserted_at)
    |> Repo.all()
  end

  @doc """
  작업 ID로 작업 상태를 조회합니다.

  ## Returns

    - `{:ok, %AgentTask{}}` - 작업 정보
    - `{:error, :not_found}` - 작업을 찾을 수 없음
  """
  def get_task(task_id) do
    case Repo.get(AgentTask, task_id) do
      nil -> {:error, :not_found}
      task -> {:ok, task}
    end
  end

  @doc """
  작업 상태를 조회합니다.

  ## Returns

    - `:pending` - 대기 중
    - `:in_progress` - 진행 중
    - `:completed` - 완료
    - `:failed` - 실패
  """
  def get_task_status(task_id) do
    case get_task(task_id) do
      {:ok, task} -> task.status
      {:error, _} -> :not_found
    end
  end

  @doc """
  특정 대화의 에이전트 간 상호작용 기록을 조회합니다.
  """
  def list_interactions(conversation_id) do
    AgentInteraction
    |> where([i], i.conversation_id == ^conversation_id)
    |> order_by([i], desc: i.inserted_at)
    |> Repo.all()
  end

  # 비공개 함수들

  defp create_interaction(
         from_agent_id,
         to_agent_id,
         conversation_id,
         interaction_type,
         message_content
       ) do
    attrs = %{
      conversation_id: conversation_id,
      from_agent_id: from_agent_id,
      to_agent_id: to_agent_id,
      interaction_type: interaction_type,
      message_content: message_content
    }

    %AgentInteraction{}
    |> AgentInteraction.changeset(attrs)
    |> Repo.insert()
  end

  defp add_result_to_interaction(interaction, additional_content) do
    updated_content = Map.merge(interaction.message_content || %{}, additional_content)

    interaction
    |> AgentInteraction.changeset(%{message_content: updated_content})
    |> Repo.update()
  end
end
