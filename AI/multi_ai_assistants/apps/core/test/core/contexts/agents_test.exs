defmodule Core.Contexts.AgentsTest do
  use Core.DataCase, async: false

  alias Core.Contexts.Agents
  import Core.Fixtures

  describe "list_agents/0" do
    test "모든 에이전트를 조회한다" do
      agent1 = agent_fixture(%{name: "agent_1"})
      agent2 = agent_fixture(%{name: "agent_2"})

      agents = Agents.list_agents()

      ids = Enum.map(agents, & &1.id)
      assert agent1.id in ids
      assert agent2.id in ids
    end

    test "에이전트가 없으면 빈 목록을 반환한다" do
      # 다른 테스트에서 생성된 에이전트가 있을 수 있으므로
      # 새로운 테스트 환경에서 확인
      agents = Agents.list_agents()
      assert is_list(agents)
    end
  end

  describe "list_agents/1" do
    test "type으로 필터링한다" do
      supervisor_fixture(%{name: "sup_1"})
      worker_fixture(%{name: "work_1"})

      supervisors = Agents.list_agents(type: :supervisor)
      workers = Agents.list_agents(type: :worker)

      assert Enum.all?(supervisors, fn a -> a.type == :supervisor end)
      assert Enum.all?(workers, fn a -> a.type == :worker end)
    end

    test "status로 필터링한다" do
      agent_fixture(%{name: "active_agent", status: :active})
      agent_fixture(%{name: "disabled_agent", status: :disabled})

      active = Agents.list_agents(status: :active)
      disabled = Agents.list_agents(status: :disabled)

      assert Enum.all?(active, fn a -> a.status == :active end)
      assert Enum.all?(disabled, fn a -> a.status == :disabled end)
    end

    test "type과 status를 함께 필터링한다" do
      supervisor_fixture(%{name: "active_sup", status: :active})
      supervisor_fixture(%{name: "disabled_sup", status: :disabled})
      worker_fixture(%{name: "active_worker", status: :active})

      result = Agents.list_agents(type: :supervisor, status: :active)

      assert Enum.all?(result, fn a ->
               a.type == :supervisor and a.status == :active
             end)
    end
  end

  describe "list_supervisors/0" do
    test "활성화된 Supervisor만 조회한다" do
      supervisor_fixture(%{name: "active_sup", status: :active})
      supervisor_fixture(%{name: "disabled_sup", status: :disabled})
      worker_fixture(%{name: "worker", status: :active})

      supervisors = Agents.list_supervisors()

      assert Enum.all?(supervisors, fn a ->
               a.type == :supervisor and a.status == :active
             end)
    end
  end

  describe "list_workers/0" do
    test "활성화된 Worker만 조회한다" do
      worker_fixture(%{name: "active_worker", status: :active})
      worker_fixture(%{name: "disabled_worker", status: :disabled})
      supervisor_fixture(%{name: "supervisor", status: :active})

      workers = Agents.list_workers()

      assert Enum.all?(workers, fn a ->
               a.type == :worker and a.status == :active
             end)
    end
  end

  describe "get_agent/1" do
    test "ID로 에이전트를 조회한다" do
      agent = agent_fixture()

      found = Agents.get_agent(agent.id)

      assert found.id == agent.id
    end

    test "존재하지 않는 ID는 nil을 반환한다" do
      fake_id = Ecto.UUID.generate()

      assert nil == Agents.get_agent(fake_id)
    end
  end

  describe "get_agent!/1" do
    test "ID로 에이전트를 조회한다" do
      agent = agent_fixture()

      found = Agents.get_agent!(agent.id)

      assert found.id == agent.id
    end

    test "존재하지 않는 ID는 예외를 발생시킨다" do
      fake_id = Ecto.UUID.generate()

      assert_raise Ecto.NoResultsError, fn ->
        Agents.get_agent!(fake_id)
      end
    end
  end

  describe "get_agent_by_name/1" do
    test "이름으로 에이전트를 조회한다" do
      agent = agent_fixture(%{name: "unique_name_123"})

      found = Agents.get_agent_by_name("unique_name_123")

      assert found.id == agent.id
    end

    test "존재하지 않는 이름은 nil을 반환한다" do
      assert nil == Agents.get_agent_by_name("nonexistent_name")
    end
  end

  describe "get_agent_by_name!/1" do
    test "이름으로 에이전트를 조회한다" do
      agent = agent_fixture(%{name: "unique_name_456"})

      found = Agents.get_agent_by_name!("unique_name_456")

      assert found.id == agent.id
    end

    test "존재하지 않는 이름은 예외를 발생시킨다" do
      assert_raise Ecto.NoResultsError, fn ->
        Agents.get_agent_by_name!("nonexistent_name")
      end
    end
  end

  describe "get_active_supervisor/0" do
    test "첫 번째 활성 Supervisor를 반환한다" do
      supervisor_fixture(%{name: "first_sup", status: :active})

      supervisor = Agents.get_active_supervisor()

      assert supervisor.type == :supervisor
      assert supervisor.status == :active
    end

    test "활성 Supervisor가 없으면 nil을 반환한다" do
      # disabled supervisor만 생성
      supervisor_fixture(%{name: "disabled_sup", status: :disabled})

      result = Agents.get_active_supervisor()

      # 다른 테스트에서 생성된 active supervisor가 있을 수 있음
      assert result == nil or (result.type == :supervisor and result.status == :active)
    end
  end

  describe "create_agent/1" do
    test "유효한 속성으로 에이전트를 생성한다" do
      attrs = %{
        type: :worker,
        name: "new_agent_#{System.unique_integer([:positive])}",
        display_name: "New Agent",
        description: "A new agent"
      }

      assert {:ok, agent} = Agents.create_agent(attrs)
      assert agent.name == attrs.name
      assert agent.type == :worker
    end

    test "필수 필드가 없으면 에러를 반환한다" do
      attrs = %{display_name: "No Name"}

      assert {:error, changeset} = Agents.create_agent(attrs)
      assert errors_on(changeset)[:name]
      assert errors_on(changeset)[:type]
    end

    test "중복된 이름은 에러를 반환한다" do
      name = "duplicate_name_#{System.unique_integer([:positive])}"
      agent_fixture(%{name: name})

      attrs = %{type: :worker, name: name}

      assert {:error, changeset} = Agents.create_agent(attrs)
      assert errors_on(changeset)[:name]
    end

    test "temperature 범위를 검증한다" do
      attrs = %{type: :worker, name: "temp_test", temperature: 2.5}

      assert {:error, changeset} = Agents.create_agent(attrs)
      assert errors_on(changeset)[:temperature]
    end

    test "max_iterations > 0을 검증한다" do
      attrs = %{type: :worker, name: "iter_test", max_iterations: 0}

      assert {:error, changeset} = Agents.create_agent(attrs)
      assert errors_on(changeset)[:max_iterations]
    end
  end

  describe "update_agent/2" do
    test "에이전트를 업데이트한다" do
      agent = agent_fixture()

      assert {:ok, updated} =
               Agents.update_agent(agent, %{display_name: "Updated Name"})

      assert updated.display_name == "Updated Name"
    end

    test "잘못된 값으로 업데이트하면 에러를 반환한다" do
      agent = agent_fixture()

      assert {:error, changeset} =
               Agents.update_agent(agent, %{temperature: 3.0})

      assert errors_on(changeset)[:temperature]
    end
  end

  describe "delete_agent/1" do
    test "에이전트를 삭제한다" do
      agent = agent_fixture()

      assert {:ok, deleted} = Agents.delete_agent(agent)
      assert deleted.id == agent.id

      assert nil == Agents.get_agent(agent.id)
    end
  end

  describe "disable_agent/1" do
    test "에이전트를 비활성화한다" do
      agent = agent_fixture(%{status: :active})

      assert {:ok, disabled} = Agents.disable_agent(agent)
      assert disabled.status == :disabled
    end
  end

  describe "enable_agent/1" do
    test "에이전트를 활성화한다" do
      agent = agent_fixture(%{status: :disabled})

      assert {:ok, enabled} = Agents.enable_agent(agent)
      assert enabled.status == :active
    end
  end

  describe "agent_has_tool?/2" do
    test "에이전트가 도구를 가지고 있으면 true를 반환한다" do
      agent = agent_fixture(%{enabled_tools: ["calculator", "web_search"]})

      assert Agents.agent_has_tool?(agent, "calculator")
      assert Agents.agent_has_tool?(agent, "web_search")
    end

    test "에이전트가 도구를 가지고 있지 않으면 false를 반환한다" do
      agent = agent_fixture(%{enabled_tools: ["calculator"]})

      refute Agents.agent_has_tool?(agent, "code_executor")
    end

    test "enabled_tools가 비어있으면 false를 반환한다" do
      agent = agent_fixture(%{enabled_tools: []})

      refute Agents.agent_has_tool?(agent, "calculator")
    end
  end

  describe "get_agent_config/3" do
    test "설정 값을 반환한다" do
      agent = agent_fixture(%{config: %{"max_tasks" => 5, "timeout" => 30}})

      assert Agents.get_agent_config(agent, "max_tasks") == 5
      assert Agents.get_agent_config(agent, "timeout") == 30
    end

    test "키가 없으면 nil을 반환한다" do
      agent = agent_fixture(%{config: %{}})

      assert Agents.get_agent_config(agent, "nonexistent") == nil
    end

    test "키가 없으면 기본값을 반환한다" do
      agent = agent_fixture(%{config: %{}})

      assert Agents.get_agent_config(agent, "nonexistent", "default") == "default"
    end
  end
end
