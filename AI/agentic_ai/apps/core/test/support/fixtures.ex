defmodule Core.Fixtures do
  @moduledoc """
  테스트용 데이터 픽스처를 생성하는 헬퍼 모듈입니다.
  """

  alias Core.Repo
  alias Core.Schema.{Agent, Conversation, AgentMemory, AgentTask, AgentInteraction}

  @doc """
  테스트용 Agent를 생성합니다.
  """
  def agent_fixture(attrs \\ %{}) do
    {:ok, agent} =
      attrs
      |> Enum.into(%{
        type: :worker,
        name: "test_worker_#{System.unique_integer([:positive])}",
        display_name: "Test Worker",
        description: "테스트용 워커 에이전트",
        system_prompt: "You are a test assistant.",
        model: "gpt-5-mini",
        temperature: 1.0,
        max_iterations: 10,
        enabled_tools: ["calculator", "web_search"],
        config: %{},
        status: :active
      })
      |> then(&Agent.changeset(%Agent{}, &1))
      |> Repo.insert()

    agent
  end

  @doc """
  Supervisor Agent를 생성합니다.
  """
  def supervisor_fixture(attrs \\ %{}) do
    agent_fixture(
      Map.merge(
        %{
          type: :supervisor,
          name: "test_supervisor_#{System.unique_integer([:positive])}",
          display_name: "Test Supervisor",
          description: "테스트용 수퍼바이저"
        },
        attrs
      )
    )
  end

  @doc """
  Worker Agent를 생성합니다.
  """
  def worker_fixture(attrs \\ %{}) do
    agent_fixture(
      Map.merge(
        %{
          type: :worker,
          name: "test_worker_#{System.unique_integer([:positive])}",
          display_name: "Test Worker"
        },
        attrs
      )
    )
  end

  @doc """
  Restructure Worker Agent를 생성합니다.
  답변을 결론 우선 구조로 재구성하는 에이전트입니다.
  """
  def restructure_worker_fixture(attrs \\ %{}) do
    agent_fixture(
      Map.merge(
        %{
          type: :worker,
          name: "restructure_worker_#{System.unique_integer([:positive])}",
          display_name: "Restructure Worker",
          description: "답변을 결론 우선 구조로 재구성하는 Worker",
          system_prompt: """
          당신은 텍스트를 결론 우선 구조로 재구성하는 전문 Worker 에이전트입니다.
          주어진 텍스트를 다음 구조로 재구성합니다:
          1. 핵심 결론 (1-2문장)
          2. 주요 근거 (2-4개 항목)
          3. 세부 사항 (필요한 경우)
          """,
          temperature: 0.7,
          max_iterations: 3,
          enabled_tools: [],
          config: %{
            "preserve_original_meaning" => true,
            "max_conclusion_sentences" => 2,
            "min_supporting_points" => 2
          }
        },
        attrs
      )
    )
  end

  @doc """
  Emoji Worker Agent를 생성합니다.
  답변에 적절한 이모지를 추가하는 에이전트입니다.
  """
  def emoji_worker_fixture(attrs \\ %{}) do
    agent_fixture(
      Map.merge(
        %{
          type: :worker,
          name: "emoji_worker_#{System.unique_integer([:positive])}",
          display_name: "Emoji Worker",
          description: "답변에 적절한 이모지를 추가하여 가독성과 친근감을 높이는 Worker",
          system_prompt: """
          당신은 텍스트에 적절한 이모지를 추가하는 전문 Worker 에이전트입니다.
          주어진 텍스트에 맥락에 맞는 이모지를 추가하여 가독성과 친근감을 높입니다.
          """,
          temperature: 0.8,
          max_iterations: 3,
          enabled_tools: [],
          config: %{
            "emoji_density" => "moderate",
            "prefer_unicode_emoji" => true,
            "max_emoji_per_paragraph" => 3
          }
        },
        attrs
      )
    )
  end

  @doc """
  테스트용 Conversation을 생성합니다.
  """
  def conversation_fixture(attrs \\ %{}) do
    {:ok, conversation} =
      attrs
      |> Enum.into(%{
        title: "Test Conversation",
        status: :active
      })
      |> then(&Conversation.changeset(%Conversation{}, &1))
      |> Repo.insert()

    conversation
  end

  @doc """
  테스트용 AgentMemory를 생성합니다.
  """
  def agent_memory_fixture(agent, attrs \\ %{}) do
    {:ok, memory} =
      attrs
      |> Enum.into(%{
        agent_id: agent.id,
        memory_type: :learned_pattern,
        key: "test_key_#{System.unique_integer([:positive])}",
        value: %{content: "test value"},
        relevance_score: 0.8
      })
      |> then(&AgentMemory.changeset(%AgentMemory{}, &1))
      |> Repo.insert()

    memory
  end

  @doc """
  테스트용 AgentTask를 생성합니다.
  """
  def agent_task_fixture(conversation, supervisor, attrs \\ %{}) do
    {:ok, task} =
      attrs
      |> Enum.into(%{
        conversation_id: conversation.id,
        supervisor_id: supervisor.id,
        task_type: "test_task",
        description: "Test task description",
        input_data: %{},
        status: :pending,
        priority: 0
      })
      |> then(&AgentTask.changeset(%AgentTask{}, &1))
      |> Repo.insert()

    task
  end

  @doc """
  테스트용 AgentInteraction을 생성합니다.
  """
  def agent_interaction_fixture(conversation, from_agent, to_agent, attrs \\ %{}) do
    {:ok, interaction} =
      attrs
      |> Enum.into(%{
        conversation_id: conversation.id,
        from_agent_id: from_agent.id,
        to_agent_id: to_agent.id,
        interaction_type: :task_delegation,
        message_content: %{request: "test"}
      })
      |> then(&AgentInteraction.changeset(%AgentInteraction{}, &1))
      |> Repo.insert()

    interaction
  end
end
