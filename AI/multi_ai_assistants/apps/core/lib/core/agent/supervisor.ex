defmodule Core.Agent.Supervisor do
  @moduledoc """
  에이전트 프로세스를 위한 수퍼바이저.

  단일 에이전트 Worker(레거시)와 멀티 에이전트 SupervisorAgent를 모두 관리합니다.
  """
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Starts a SupervisorAgent for a conversation.

  ## Parameters

    - `agent_id` - Supervisor 에이전트 ID
    - `conversation_id` - 대화 ID

  ## Returns

    - `{:ok, pid}` - 성공 시 프로세스 PID
    - `{:error, reason}` - 실패 시 오류 원인
  """
  def start_supervisor_agent(agent_id, conversation_id) do
    spec = {Core.Agent.SupervisorAgent, agent_id: agent_id, conversation_id: conversation_id}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @doc """
  대화를 위한 단일 Worker 에이전트를 시작합니다 (레거시).

  이 함수는 하위 호환성을 위해 유지됩니다.
  멀티 에이전트 시스템의 경우 `start_supervisor_agent/2`를 사용하세요.
  """
  def start_agent(conversation_id) do
    spec = {Core.Agent.Worker, conversation_id: conversation_id}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  def stop_agent(pid) do
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end
end
