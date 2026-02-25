defmodule Core.Schema.AgentTaskTest do
  use Core.DataCase, async: false

  alias Core.Schema.AgentTask
  import Core.Fixtures

  describe "changeset/2" do
    setup do
      supervisor = supervisor_fixture()
      worker = worker_fixture()
      conversation = conversation_fixture()

      %{supervisor: supervisor, worker: worker, conversation: conversation}
    end

    test "유효한 속성으로 changeset을 생성한다", %{supervisor: supervisor, conversation: conversation} do
      attrs = %{
        conversation_id: conversation.id,
        supervisor_id: supervisor.id,
        task_type: "general",
        description: "Test task"
      }

      changeset = AgentTask.changeset(%AgentTask{}, attrs)

      assert changeset.valid?
    end

    test "conversation_id와 supervisor_id는 필수이다", %{
      supervisor: supervisor,
      conversation: conversation
    } do
      # conversation_id 누락
      changeset = AgentTask.changeset(%AgentTask{}, %{supervisor_id: supervisor.id})
      refute changeset.valid?
      assert errors_on(changeset)[:conversation_id]

      # supervisor_id 누락
      changeset = AgentTask.changeset(%AgentTask{}, %{conversation_id: conversation.id})
      refute changeset.valid?
      assert errors_on(changeset)[:supervisor_id]
    end

    test "status 기본값은 :pending이다" do
      task = %AgentTask{}
      assert task.status == :pending
    end

    test "status는 정의된 값만 허용한다", %{supervisor: supervisor, conversation: conversation} do
      valid_statuses = [:pending, :assigned, :in_progress, :completed, :failed]

      for status <- valid_statuses do
        attrs = %{
          conversation_id: conversation.id,
          supervisor_id: supervisor.id,
          status: status
        }

        changeset = AgentTask.changeset(%AgentTask{}, attrs)
        assert changeset.valid?, "status #{status} should be valid"
      end
    end

    test "priority 기본값은 0이다" do
      task = %AgentTask{}
      assert task.priority == 0
    end

    test "모든 필드를 설정할 수 있다", %{supervisor: supervisor, worker: worker, conversation: conversation} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      attrs = %{
        conversation_id: conversation.id,
        supervisor_id: supervisor.id,
        worker_id: worker.id,
        task_type: "calculation",
        description: "Calculate something",
        input_data: %{expression: "2 + 2"},
        output_data: %{result: 4},
        status: :completed,
        priority: 5,
        started_at: now,
        completed_at: now,
        error_message: nil
      }

      changeset = AgentTask.changeset(%AgentTask{}, attrs)

      assert changeset.valid?
    end

    test "input_data와 output_data는 맵이다", %{supervisor: supervisor, conversation: conversation} do
      attrs = %{
        conversation_id: conversation.id,
        supervisor_id: supervisor.id,
        input_data: %{
          request: "Calculate",
          params: %{a: 1, b: 2}
        },
        output_data: %{
          result: 3,
          metadata: %{execution_time: 100}
        }
      }

      changeset = AgentTask.changeset(%AgentTask{}, attrs)
      assert changeset.valid?
    end

    test "error_message는 문자열이다", %{supervisor: supervisor, conversation: conversation} do
      attrs = %{
        conversation_id: conversation.id,
        supervisor_id: supervisor.id,
        status: :failed,
        error_message: "Task failed due to timeout"
      }

      changeset = AgentTask.changeset(%AgentTask{}, attrs)
      assert changeset.valid?
    end
  end

  describe "DB 작업" do
    setup do
      supervisor = supervisor_fixture()
      worker = worker_fixture()
      conversation = conversation_fixture()

      %{supervisor: supervisor, worker: worker, conversation: conversation}
    end

    test "작업을 생성하고 조회할 수 있다", %{supervisor: supervisor, conversation: conversation} do
      attrs = %{
        conversation_id: conversation.id,
        supervisor_id: supervisor.id,
        task_type: "test",
        description: "DB test task"
      }

      {:ok, task} =
        %AgentTask{}
        |> AgentTask.changeset(attrs)
        |> Repo.insert()

      found = Repo.get(AgentTask, task.id)
      assert found.description == "DB test task"
      assert found.status == :pending
    end

    test "작업 상태를 업데이트할 수 있다", %{supervisor: supervisor, conversation: conversation} do
      {:ok, task} =
        %AgentTask{}
        |> AgentTask.changeset(%{
          conversation_id: conversation.id,
          supervisor_id: supervisor.id
        })
        |> Repo.insert()

      {:ok, updated} =
        task
        |> AgentTask.changeset(%{status: :in_progress, started_at: DateTime.utc_now()})
        |> Repo.update()

      assert updated.status == :in_progress
      assert updated.started_at != nil
    end

    test "존재하지 않는 conversation_id는 외래키 에러를 발생시킨다", %{supervisor: supervisor} do
      attrs = %{
        conversation_id: Ecto.UUID.generate(),
        supervisor_id: supervisor.id
      }

      changeset = AgentTask.changeset(%AgentTask{}, attrs)

      # SQLite에서는 외래키 위반 시 Ecto.ConstraintError 예외가 발생
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(changeset)
      end
    end

    test "존재하지 않는 supervisor_id는 외래키 에러를 발생시킨다", %{conversation: conversation} do
      attrs = %{
        conversation_id: conversation.id,
        supervisor_id: Ecto.UUID.generate()
      }

      changeset = AgentTask.changeset(%AgentTask{}, attrs)

      # SQLite에서는 외래키 위반 시 Ecto.ConstraintError 예외가 발생
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(changeset)
      end
    end

    test "worker_id는 선택적이다", %{supervisor: supervisor, conversation: conversation} do
      attrs = %{
        conversation_id: conversation.id,
        supervisor_id: supervisor.id
        # worker_id 없음
      }

      {:ok, task} =
        %AgentTask{}
        |> AgentTask.changeset(attrs)
        |> Repo.insert()

      assert task.worker_id == nil
    end
  end
end
