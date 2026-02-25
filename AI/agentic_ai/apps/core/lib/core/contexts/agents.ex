defmodule Core.Contexts.Agents do
  @moduledoc """
  에이전트 관리를 위한 Context 레이어입니다.
  """

  import Ecto.Query, warn: false
  alias Core.Repo
  alias Core.Schema.{Agent, AgentInteraction}

  @doc """
  모든 에이전트를 조회합니다.

  ## Examples

      iex> list_agents()
      [%Agent{}, ...]
  """
  def list_agents do
    Repo.all(Agent)
  end

  @doc """
  필터 조건에 맞는 에이전트를 조회합니다.

  ## 옵션

    - `:type` - 에이전트 타입 (:supervisor | :worker)
    - `:status` - 상태 (:active | :disabled)

  ## Examples

      iex> list_agents(type: :supervisor, status: :active)
      [%Agent{}, ...]
  """
  def list_agents(opts) do
    query = from(a in Agent)

    query =
      Enum.reduce(opts, query, fn
        {:type, type}, query ->
          from(a in query, where: a.type == ^type)

        {:status, status}, query ->
          from(a in query, where: a.status == ^status)

        _, query ->
          query
      end)

    Repo.all(query)
  end

  @doc """
  모든 Supervisor 에이전트를 조회합니다.

  ## Examples

      iex> list_supervisors()
      [%Agent{type: :supervisor}, ...]
  """
  def list_supervisors do
    list_agents(type: :supervisor, status: :active)
  end

  @doc """
  모든 Worker 에이전트를 조회합니다.

  ## Examples

      iex> list_workers()
      [%Agent{type: :worker}, ...]
  """
  def list_workers do
    list_agents(type: :worker, status: :active)
  end

  @doc """
  ID로 에이전트를 조회합니다.
  에이전트가 없으면 nil을 반환합니다.

  ## Examples

      iex> get_agent(123)
      %Agent{}

      iex> get_agent(456)
      nil
  """
  def get_agent(id) do
    Repo.get(Agent, id)
  end

  @doc """
  ID로 에이전트를 조회합니다.
  에이전트가 없으면 Ecto.NoResultsError를 발생시킵니다.

  ## Examples

      iex> get_agent!(123)
      %Agent{}

      iex> get_agent!(456)
      ** (Ecto.NoResultsError)
  """
  def get_agent!(id) do
    Repo.get!(Agent, id)
  end

  @doc """
  이름으로 에이전트를 조회합니다.
  에이전트가 없으면 nil을 반환합니다.

  ## Examples

      iex> get_agent_by_name("main_supervisor")
      %Agent{}

      iex> get_agent_by_name("unknown")
      nil
  """
  def get_agent_by_name(name) do
    Repo.get_by(Agent, name: name)
  end

  @doc """
  이름으로 에이전트를 조회합니다.
  에이전트가 없으면 Ecto.NoResultsError를 발생시킵니다.

  ## Examples

      iex> get_agent_by_name!("main_supervisor")
      %Agent{}

      iex> get_agent_by_name!("unknown")
      ** (Ecto.NoResultsError)
  """
  def get_agent_by_name!(name) do
    case get_agent_by_name(name) do
      nil -> raise Ecto.NoResultsError, queryable: Agent
      agent -> agent
    end
  end

  @doc """
  활성화된 첫 번째 Supervisor 에이전트를 조회합니다.
  주로 기본 Supervisor를 가져올 때 사용합니다.

  ## Examples

      iex> get_active_supervisor()
      %Agent{type: :supervisor, status: :active}
  """
  def get_active_supervisor do
    query =
      from(a in Agent,
        where: a.type == :supervisor and a.status == :active,
        limit: 1
      )

    Repo.one(query)
  end

  @doc """
  새로운 에이전트를 생성합니다.

  ## Examples

      iex> create_agent(%{name: "my_agent", type: :worker})
      {:ok, %Agent{}}

      iex> create_agent(%{name: nil})
      {:error, %Ecto.Changeset{}}
  """
  def create_agent(attrs \\ %{}) do
    %Agent{}
    |> Agent.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  에이전트를 업데이트합니다.

  ## Examples

      iex> update_agent(agent, %{display_name: "New Name"})
      {:ok, %Agent{}}

      iex> update_agent(agent, %{name: nil})
      {:error, %Ecto.Changeset{}}
  """
  def update_agent(%Agent{} = agent, attrs) do
    agent
    |> Agent.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  에이전트를 삭제합니다.

  ## Examples

      iex> delete_agent(agent)
      {:ok, %Agent{}}

      iex> delete_agent(agent)
      {:error, %Ecto.Changeset{}}
  """
  def delete_agent(%Agent{} = agent) do
    Repo.delete(agent)
  end

  @doc """
  에이전트를 비활성화합니다.

  ## Examples

      iex> disable_agent(agent)
      {:ok, %Agent{status: :disabled}}
  """
  def disable_agent(%Agent{} = agent) do
    update_agent(agent, %{status: :disabled})
  end

  @doc """
  에이전트를 활성화합니다.

  ## Examples

      iex> enable_agent(agent)
      {:ok, %Agent{status: :active}}
  """
  def enable_agent(%Agent{} = agent) do
    update_agent(agent, %{status: :active})
  end

  @doc """
  에이전트가 특정 도구를 사용할 수 있는지 확인합니다.

  ## Examples

      iex> agent_has_tool?(agent, "calculator")
      true

      iex> agent_has_tool?(agent, "unknown_tool")
      false
  """
  def agent_has_tool?(%Agent{enabled_tools: tools}, tool_name) do
    tool_name in tools
  end

  @doc """
  에이전트의 설정 값을 조회합니다.

  ## Examples

      iex> get_agent_config(agent, "max_concurrent_tasks")
      3

      iex> get_agent_config(agent, "unknown_key", "default")
      "default"
  """
  def get_agent_config(%Agent{config: config}, key, default \\ nil) do
    Map.get(config, key, default)
  end

  @doc """
  특정 대화에서 사용된 에이전트 이력을 순서대로 조회합니다.

  `task_delegation` 타입의 상호작용을 시간순으로 정렬하여
  Supervisor와 Worker 에이전트가 어떤 순서로 사용되었는지 반환합니다.

  각 task_delegation에서:
  - from_agent (Supervisor): 요청을 받고 위임함
  - to_agent (Worker): 실제 작업 수행

  ## Returns

    - 순서대로 정렬된 에이전트 사용 이력 리스트
    - 각 항목: `%{order: 순번, agent: %Agent{}, role: :supervisor | :worker, timestamp: DateTime}`

  ## Examples

      iex> list_agent_usage_history(conversation_id)
      [
        %{order: 1, agent: %Agent{name: "main_supervisor"}, role: :supervisor, timestamp: ~U[...]},
        %{order: 2, agent: %Agent{name: "calculator"}, role: :worker, timestamp: ~U[...]}
      ]
  """
  def list_agent_usage_history(conversation_id) do
    list_agent_usage_history(conversation_id, nil)
  end

  @doc """
  특정 시간 이후에 사용된 에이전트 이력만 조회합니다.

  한 번의 질문에 대한 에이전트 실행 순서를 표시할 때 사용합니다.
  `since` 파라미터가 nil이면 전체 이력을 반환합니다.

  ## Parameters

    - `conversation_id` - 대화 ID
    - `since` - 이 시간 이후의 이력만 조회 (DateTime 또는 nil)

  ## Examples

      iex> list_agent_usage_history(conversation_id, ~U[2024-01-01 12:00:00Z])
      [%{order: 1, agent: %Agent{}, ...}]
  """
  def list_agent_usage_history(conversation_id, since) do
    query =
      from(i in AgentInteraction,
        where: i.conversation_id == ^conversation_id and i.interaction_type == :task_delegation,
        order_by: [asc: i.inserted_at],
        preload: [:from_agent, :to_agent]
      )

    query =
      if since do
        from(i in query, where: i.inserted_at >= ^since)
      else
        query
      end

    query
    |> Repo.all()
    |> Enum.flat_map_reduce(1, fn interaction, order ->
      # Supervisor가 먼저, Worker가 다음
      entries = [
        %{
          order: order,
          agent: interaction.from_agent,
          role: :supervisor,
          timestamp: interaction.inserted_at
        },
        %{
          order: order + 1,
          agent: interaction.to_agent,
          role: :worker,
          timestamp: interaction.inserted_at
        }
      ]

      {entries, order + 2}
    end)
    |> elem(0)
  end
end
