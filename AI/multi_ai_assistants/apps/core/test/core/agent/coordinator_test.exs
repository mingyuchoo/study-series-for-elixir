defmodule Core.Agent.CoordinatorTest do
  use Core.DataCase, async: false

  alias Core.Agent.Coordinator
  alias Core.Schema.AgentTask
  import Core.Fixtures

  setup do
    supervisor = supervisor_fixture()
    worker = worker_fixture()
    conversation = conversation_fixture()

    %{supervisor: supervisor, worker: worker, conversation: conversation}
  end

  describe "list_tasks/1" do
    test "대화 ID로 작업 목록을 조회한다", %{supervisor: supervisor, conversation: conversation} do
      # 작업 생성
      agent_task_fixture(conversation, supervisor, %{description: "Task 1"})
      agent_task_fixture(conversation, supervisor, %{description: "Task 2"})

      tasks = Coordinator.list_tasks(conversation.id)

      assert length(tasks) == 2
    end

    test "최신 작업이 먼저 나온다 (내림차순)", %{supervisor: supervisor, conversation: conversation} do
      {:ok, _task1} = create_task(conversation, supervisor, "First")
      # SQLite 타임스탬프는 초 단위이므로 충분히 대기
      Process.sleep(1100)
      {:ok, _task2} = create_task(conversation, supervisor, "Second")

      tasks = Coordinator.list_tasks(conversation.id)

      # 내림차순이면 최신(Second)이 먼저
      assert hd(tasks).description == "Second"
      assert List.last(tasks).description == "First"
    end

    test "다른 대화의 작업은 조회되지 않는다", %{supervisor: supervisor, conversation: conversation} do
      other_conversation = conversation_fixture()

      agent_task_fixture(conversation, supervisor, %{description: "This conv"})
      agent_task_fixture(other_conversation, supervisor, %{description: "Other conv"})

      tasks = Coordinator.list_tasks(conversation.id)

      assert length(tasks) == 1
      assert hd(tasks).description == "This conv"
    end

    test "작업이 없으면 빈 목록을 반환한다", %{conversation: conversation} do
      tasks = Coordinator.list_tasks(conversation.id)
      assert tasks == []
    end
  end

  describe "get_task/1" do
    test "작업 ID로 작업을 조회한다", %{supervisor: supervisor, conversation: conversation} do
      task = agent_task_fixture(conversation, supervisor)

      assert {:ok, found} = Coordinator.get_task(task.id)
      assert found.id == task.id
    end

    test "존재하지 않는 작업 ID는 에러를 반환한다" do
      fake_id = Ecto.UUID.generate()
      assert {:error, :not_found} = Coordinator.get_task(fake_id)
    end
  end

  describe "get_task_status/1" do
    test "작업 상태를 반환한다", %{supervisor: supervisor, conversation: conversation} do
      task = agent_task_fixture(conversation, supervisor, %{status: :in_progress})

      status = Coordinator.get_task_status(task.id)
      assert status == :in_progress
    end

    test "존재하지 않는 작업은 :not_found를 반환한다" do
      fake_id = Ecto.UUID.generate()
      assert :not_found = Coordinator.get_task_status(fake_id)
    end

    test "각 상태값을 올바르게 반환한다", %{supervisor: supervisor, conversation: conversation} do
      for status <- [:pending, :assigned, :in_progress, :completed, :failed] do
        task = agent_task_fixture(conversation, supervisor, %{status: status})
        assert Coordinator.get_task_status(task.id) == status
      end
    end
  end

  describe "list_interactions/1" do
    test "대화 ID로 상호작용 목록을 조회한다", %{
      supervisor: supervisor,
      worker: worker,
      conversation: conversation
    } do
      agent_interaction_fixture(conversation, supervisor, worker, %{
        interaction_type: :task_delegation,
        message_content: %{request: "test1"}
      })

      agent_interaction_fixture(conversation, worker, supervisor, %{
        interaction_type: :result_return,
        message_content: %{result: "done"}
      })

      interactions = Coordinator.list_interactions(conversation.id)

      assert length(interactions) == 2
    end

    test "최신 상호작용이 먼저 나온다", %{supervisor: supervisor, worker: worker, conversation: conversation} do
      agent_interaction_fixture(conversation, supervisor, worker, %{
        interaction_type: :task_delegation,
        message_content: %{order: 1}
      })

      # SQLite 타임스탬프는 초 단위이므로 충분히 대기
      Process.sleep(1100)

      agent_interaction_fixture(conversation, worker, supervisor, %{
        interaction_type: :result_return,
        message_content: %{order: 2}
      })

      interactions = Coordinator.list_interactions(conversation.id)

      # 내림차순이면 최신(order: 2)이 먼저
      assert hd(interactions).message_content["order"] == 2
    end

    test "다른 대화의 상호작용은 조회되지 않는다", %{
      supervisor: supervisor,
      worker: worker,
      conversation: conversation
    } do
      other_conv = conversation_fixture()

      agent_interaction_fixture(conversation, supervisor, worker)
      agent_interaction_fixture(other_conv, supervisor, worker)

      interactions = Coordinator.list_interactions(conversation.id)

      assert length(interactions) == 1
    end
  end

  describe "send_task/4" do
    @tag :skip
    test "Worker에게 작업을 전달하고 상호작용을 기록한다" do
      # 이 테스트는 실제 WorkerAgent 프로세스가 필요합니다.
      # GenServer 기반 통합 테스트로 별도 작성해야 합니다.
    end
  end

  # Helper functions

  defp create_task(conversation, supervisor, description) do
    attrs = %{
      conversation_id: conversation.id,
      supervisor_id: supervisor.id,
      task_type: "test",
      description: description,
      status: :pending
    }

    %AgentTask{}
    |> AgentTask.changeset(attrs)
    |> Repo.insert()
  end
end
