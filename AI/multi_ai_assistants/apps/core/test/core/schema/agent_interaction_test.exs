defmodule Core.Schema.AgentInteractionTest do
  use Core.DataCase, async: false

  alias Core.Schema.AgentInteraction
  import Core.Fixtures

  describe "changeset/2" do
    setup do
      supervisor = supervisor_fixture()
      worker = worker_fixture()
      conversation = conversation_fixture()

      %{supervisor: supervisor, worker: worker, conversation: conversation}
    end

    test "유효한 속성으로 changeset을 생성한다", %{
      supervisor: supervisor,
      worker: worker,
      conversation: conversation
    } do
      attrs = %{
        conversation_id: conversation.id,
        from_agent_id: supervisor.id,
        to_agent_id: worker.id,
        interaction_type: :task_delegation,
        message_content: %{request: "Do something"}
      }

      changeset = AgentInteraction.changeset(%AgentInteraction{}, attrs)

      assert changeset.valid?
    end

    test "필수 필드가 누락되면 유효하지 않다", %{
      supervisor: supervisor,
      worker: worker,
      conversation: conversation
    } do
      # conversation_id 누락
      changeset =
        AgentInteraction.changeset(%AgentInteraction{}, %{
          from_agent_id: supervisor.id,
          to_agent_id: worker.id,
          interaction_type: :task_delegation
        })

      refute changeset.valid?
      assert errors_on(changeset)[:conversation_id]

      # from_agent_id 누락
      changeset =
        AgentInteraction.changeset(%AgentInteraction{}, %{
          conversation_id: conversation.id,
          to_agent_id: worker.id,
          interaction_type: :task_delegation
        })

      refute changeset.valid?
      assert errors_on(changeset)[:from_agent_id]

      # to_agent_id 누락
      changeset =
        AgentInteraction.changeset(%AgentInteraction{}, %{
          conversation_id: conversation.id,
          from_agent_id: supervisor.id,
          interaction_type: :task_delegation
        })

      refute changeset.valid?
      assert errors_on(changeset)[:to_agent_id]

      # interaction_type 누락
      changeset =
        AgentInteraction.changeset(%AgentInteraction{}, %{
          conversation_id: conversation.id,
          from_agent_id: supervisor.id,
          to_agent_id: worker.id
        })

      refute changeset.valid?
      assert errors_on(changeset)[:interaction_type]
    end

    test "interaction_type은 정의된 값만 허용한다", %{
      supervisor: supervisor,
      worker: worker,
      conversation: conversation
    } do
      valid_types = [:task_delegation, :result_return, :status_update]

      for type <- valid_types do
        attrs = %{
          conversation_id: conversation.id,
          from_agent_id: supervisor.id,
          to_agent_id: worker.id,
          interaction_type: type
        }

        changeset = AgentInteraction.changeset(%AgentInteraction{}, attrs)
        assert changeset.valid?, "interaction_type #{type} should be valid"
      end
    end

    test "message_content는 맵이다", %{
      supervisor: supervisor,
      worker: worker,
      conversation: conversation
    } do
      attrs = %{
        conversation_id: conversation.id,
        from_agent_id: supervisor.id,
        to_agent_id: worker.id,
        interaction_type: :task_delegation,
        message_content: %{
          request: "Calculate 2 + 2",
          context: %{priority: "high"},
          metadata: %{timestamp: "2024-01-01"}
        }
      }

      changeset = AgentInteraction.changeset(%AgentInteraction{}, attrs)
      assert changeset.valid?
    end

    test "message_content는 선택적이다", %{
      supervisor: supervisor,
      worker: worker,
      conversation: conversation
    } do
      attrs = %{
        conversation_id: conversation.id,
        from_agent_id: supervisor.id,
        to_agent_id: worker.id,
        interaction_type: :task_delegation
        # message_content 없음
      }

      changeset = AgentInteraction.changeset(%AgentInteraction{}, attrs)
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

    test "상호작용을 생성하고 조회할 수 있다", %{
      supervisor: supervisor,
      worker: worker,
      conversation: conversation
    } do
      attrs = %{
        conversation_id: conversation.id,
        from_agent_id: supervisor.id,
        to_agent_id: worker.id,
        interaction_type: :task_delegation,
        message_content: %{test: "data"}
      }

      {:ok, interaction} =
        %AgentInteraction{}
        |> AgentInteraction.changeset(attrs)
        |> Repo.insert()

      found = Repo.get(AgentInteraction, interaction.id)
      assert found.interaction_type == :task_delegation
      assert found.message_content == %{"test" => "data"}
    end

    test "inserted_at이 자동으로 설정된다", %{
      supervisor: supervisor,
      worker: worker,
      conversation: conversation
    } do
      attrs = %{
        conversation_id: conversation.id,
        from_agent_id: supervisor.id,
        to_agent_id: worker.id,
        interaction_type: :task_delegation
      }

      {:ok, interaction} =
        %AgentInteraction{}
        |> AgentInteraction.changeset(attrs)
        |> Repo.insert()

      assert interaction.inserted_at != nil
    end

    test "updated_at 필드가 없다", %{
      supervisor: supervisor,
      worker: worker,
      conversation: conversation
    } do
      # AgentInteraction은 insert-only 모델 (updated_at: false)
      attrs = %{
        conversation_id: conversation.id,
        from_agent_id: supervisor.id,
        to_agent_id: worker.id,
        interaction_type: :task_delegation
      }

      {:ok, interaction} =
        %AgentInteraction{}
        |> AgentInteraction.changeset(attrs)
        |> Repo.insert()

      # updated_at 필드가 스키마에 없음
      refute Map.has_key?(interaction, :updated_at) or
               (Map.has_key?(interaction, :updated_at) and interaction.updated_at == nil)
    end

    test "존재하지 않는 conversation_id는 외래키 에러를 발생시킨다", %{supervisor: supervisor, worker: worker} do
      attrs = %{
        conversation_id: Ecto.UUID.generate(),
        from_agent_id: supervisor.id,
        to_agent_id: worker.id,
        interaction_type: :task_delegation
      }

      changeset = AgentInteraction.changeset(%AgentInteraction{}, attrs)

      # SQLite에서는 외래키 위반 시 Ecto.ConstraintError 예외가 발생
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(changeset)
      end
    end

    test "존재하지 않는 from_agent_id는 외래키 에러를 발생시킨다", %{worker: worker, conversation: conversation} do
      attrs = %{
        conversation_id: conversation.id,
        from_agent_id: Ecto.UUID.generate(),
        to_agent_id: worker.id,
        interaction_type: :task_delegation
      }

      changeset = AgentInteraction.changeset(%AgentInteraction{}, attrs)

      # SQLite에서는 외래키 위반 시 Ecto.ConstraintError 예외가 발생
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(changeset)
      end
    end

    test "존재하지 않는 to_agent_id는 외래키 에러를 발생시킨다", %{
      supervisor: supervisor,
      conversation: conversation
    } do
      attrs = %{
        conversation_id: conversation.id,
        from_agent_id: supervisor.id,
        to_agent_id: Ecto.UUID.generate(),
        interaction_type: :task_delegation
      }

      changeset = AgentInteraction.changeset(%AgentInteraction{}, attrs)

      # SQLite에서는 외래키 위반 시 Ecto.ConstraintError 예외가 발생
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(changeset)
      end
    end
  end

  describe "interaction_type 시나리오" do
    setup do
      supervisor = supervisor_fixture()
      worker = worker_fixture()
      conversation = conversation_fixture()

      %{supervisor: supervisor, worker: worker, conversation: conversation}
    end

    test "task_delegation: Supervisor → Worker", %{
      supervisor: supervisor,
      worker: worker,
      conversation: conversation
    } do
      attrs = %{
        conversation_id: conversation.id,
        from_agent_id: supervisor.id,
        to_agent_id: worker.id,
        interaction_type: :task_delegation,
        message_content: %{task: "Calculate 2 + 2"}
      }

      {:ok, interaction} =
        %AgentInteraction{}
        |> AgentInteraction.changeset(attrs)
        |> Repo.insert()

      assert interaction.interaction_type == :task_delegation
      assert interaction.from_agent_id == supervisor.id
      assert interaction.to_agent_id == worker.id
    end

    test "result_return: Worker → Supervisor", %{
      supervisor: supervisor,
      worker: worker,
      conversation: conversation
    } do
      attrs = %{
        conversation_id: conversation.id,
        from_agent_id: worker.id,
        to_agent_id: supervisor.id,
        interaction_type: :result_return,
        message_content: %{result: "4"}
      }

      {:ok, interaction} =
        %AgentInteraction{}
        |> AgentInteraction.changeset(attrs)
        |> Repo.insert()

      assert interaction.interaction_type == :result_return
      assert interaction.from_agent_id == worker.id
      assert interaction.to_agent_id == supervisor.id
    end

    test "status_update: 상태 변경 알림", %{
      supervisor: supervisor,
      worker: worker,
      conversation: conversation
    } do
      attrs = %{
        conversation_id: conversation.id,
        from_agent_id: worker.id,
        to_agent_id: supervisor.id,
        interaction_type: :status_update,
        message_content: %{status: "in_progress", progress: 50}
      }

      {:ok, interaction} =
        %AgentInteraction{}
        |> AgentInteraction.changeset(attrs)
        |> Repo.insert()

      assert interaction.interaction_type == :status_update
    end
  end
end
