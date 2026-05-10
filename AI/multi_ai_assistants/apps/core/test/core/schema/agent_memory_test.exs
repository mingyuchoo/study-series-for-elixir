defmodule Core.Schema.AgentMemoryTest do
  use Core.DataCase, async: false

  alias Core.Schema.AgentMemory
  import Core.Fixtures

  describe "changeset/2" do
    setup do
      agent = agent_fixture()
      %{agent: agent}
    end

    test "유효한 속성으로 changeset을 생성한다", %{agent: agent} do
      attrs = %{
        agent_id: agent.id,
        memory_type: :learned_pattern,
        key: "test_key",
        value: %{content: "test value"}
      }

      changeset = AgentMemory.changeset(%AgentMemory{}, attrs)

      assert changeset.valid?
    end

    test "agent_id, memory_type, key는 필수이다", %{agent: agent} do
      # agent_id 누락
      changeset =
        AgentMemory.changeset(%AgentMemory{}, %{
          memory_type: :learned_pattern,
          key: "test"
        })

      refute changeset.valid?
      assert errors_on(changeset)[:agent_id]

      # memory_type 누락
      changeset =
        AgentMemory.changeset(%AgentMemory{}, %{
          agent_id: agent.id,
          key: "test"
        })

      refute changeset.valid?
      assert errors_on(changeset)[:memory_type]

      # key 누락
      changeset =
        AgentMemory.changeset(%AgentMemory{}, %{
          agent_id: agent.id,
          memory_type: :learned_pattern
        })

      refute changeset.valid?
      assert errors_on(changeset)[:key]
    end

    test "memory_type은 정의된 값만 허용한다", %{agent: agent} do
      valid_types = [
        :conversation_summary,
        :learned_pattern,
        :project_context,
        :performance_metric
      ]

      for type <- valid_types do
        changeset =
          AgentMemory.changeset(%AgentMemory{}, %{
            agent_id: agent.id,
            memory_type: type,
            key: "test"
          })

        assert changeset.valid?, "memory_type #{type} should be valid"
      end
    end

    test "선택적 필드를 설정할 수 있다", %{agent: agent} do
      conversation = conversation_fixture()
      expires_at = DateTime.add(DateTime.utc_now(), 3600, :second)

      attrs = %{
        agent_id: agent.id,
        memory_type: :project_context,
        key: "context_key",
        value: %{data: "test"},
        metadata: %{source: "user", priority: 1},
        relevance_score: 0.85,
        expires_at: expires_at,
        conversation_id: conversation.id
      }

      changeset = AgentMemory.changeset(%AgentMemory{}, attrs)

      assert changeset.valid?
    end

    test "relevance_score는 실수 값이다", %{agent: agent} do
      for score <- [0.0, 0.5, 1.0] do
        attrs = %{
          agent_id: agent.id,
          memory_type: :learned_pattern,
          key: "test",
          relevance_score: score
        }

        changeset = AgentMemory.changeset(%AgentMemory{}, attrs)
        assert changeset.valid?, "relevance_score #{score} should be valid"
      end
    end

    test "value는 맵이다", %{agent: agent} do
      attrs = %{
        agent_id: agent.id,
        memory_type: :learned_pattern,
        key: "test",
        value: %{
          pattern: "Always log errors",
          examples: ["example1", "example2"],
          nested: %{key: "value"}
        }
      }

      changeset = AgentMemory.changeset(%AgentMemory{}, attrs)
      assert changeset.valid?
    end
  end

  describe "DB 작업" do
    setup do
      agent = agent_fixture()
      %{agent: agent}
    end

    test "메모리를 생성하고 조회할 수 있다", %{agent: agent} do
      attrs = %{
        agent_id: agent.id,
        memory_type: :learned_pattern,
        key: "db_test_key",
        value: %{content: "test"}
      }

      {:ok, memory} =
        %AgentMemory{}
        |> AgentMemory.changeset(attrs)
        |> Repo.insert()

      found = Repo.get(AgentMemory, memory.id)
      assert found.key == "db_test_key"
      assert found.value == %{"content" => "test"}
    end

    test "존재하지 않는 agent_id는 외래키 에러를 발생시킨다" do
      attrs = %{
        agent_id: Ecto.UUID.generate(),
        memory_type: :learned_pattern,
        key: "test"
      }

      changeset = AgentMemory.changeset(%AgentMemory{}, attrs)

      # SQLite에서는 외래키 위반 시 Ecto.ConstraintError 예외가 발생
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(changeset)
      end
    end
  end
end
