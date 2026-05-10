defmodule Core.Agent.MemoryManagerTest do
  use Core.DataCase, async: false

  alias Core.Agent.MemoryManager
  import Core.Fixtures

  setup do
    agent = supervisor_fixture()
    %{agent: agent}
  end

  describe "store/5" do
    test "새로운 메모리를 저장한다", %{agent: agent} do
      assert {:ok, memory} =
               MemoryManager.store(
                 agent.id,
                 :learned_pattern,
                 "error_handling",
                 %{pattern: "Always log errors"}
               )

      assert memory.agent_id == agent.id
      assert memory.memory_type == :learned_pattern
      assert memory.key == "error_handling"
      assert memory.value == %{pattern: "Always log errors"}
    end

    test "옵션으로 메타데이터를 설정할 수 있다", %{agent: agent} do
      {:ok, memory} =
        MemoryManager.store(
          agent.id,
          :project_context,
          "project_info",
          %{name: "Test Project"},
          metadata: %{source: "user"}
        )

      assert memory.metadata == %{source: "user"}
    end

    test "옵션으로 관련성 점수를 설정할 수 있다", %{agent: agent} do
      {:ok, memory} =
        MemoryManager.store(
          agent.id,
          :learned_pattern,
          "important_pattern",
          %{},
          relevance_score: 0.95
        )

      assert memory.relevance_score == 0.95
    end

    test "옵션으로 만료 시간을 설정할 수 있다", %{agent: agent} do
      expires_at = DateTime.add(DateTime.utc_now(), 3600, :second)

      {:ok, memory} =
        MemoryManager.store(
          agent.id,
          :performance_metric,
          "temp_metric",
          %{},
          expires_at: expires_at
        )

      assert memory.expires_at != nil
    end

    test "동일한 키로 저장 시 기존 메모리를 업데이트한다 (upsert)", %{agent: agent} do
      # 첫 번째 저장
      {:ok, first} =
        MemoryManager.store(
          agent.id,
          :learned_pattern,
          "pattern_key",
          %{version: 1}
        )

      # 같은 키로 다시 저장
      {:ok, second} =
        MemoryManager.store(
          agent.id,
          :learned_pattern,
          "pattern_key",
          %{version: 2}
        )

      # 동일한 레코드가 업데이트됨
      assert first.id == second.id
      assert second.value == %{version: 2}

      # DB에 하나의 레코드만 존재
      memories = MemoryManager.retrieve(agent.id, :learned_pattern, key: "pattern_key")
      assert length(memories) == 1
    end

    test "conversation_id를 연결할 수 있다", %{agent: agent} do
      conversation = conversation_fixture()

      {:ok, memory} =
        MemoryManager.store(
          agent.id,
          :conversation_summary,
          "summary_1",
          %{summary: "Test conversation"},
          conversation_id: conversation.id
        )

      assert memory.conversation_id == conversation.id
    end
  end

  describe "retrieve/3" do
    test "agent_id와 memory_type으로 메모리를 검색한다", %{agent: agent} do
      {:ok, _} = MemoryManager.store(agent.id, :learned_pattern, "key1", %{a: 1})
      {:ok, _} = MemoryManager.store(agent.id, :learned_pattern, "key2", %{b: 2})
      {:ok, _} = MemoryManager.store(agent.id, :project_context, "key3", %{c: 3})

      memories = MemoryManager.retrieve(agent.id, :learned_pattern)

      assert length(memories) == 2
      assert Enum.all?(memories, fn m -> m.memory_type == :learned_pattern end)
    end

    test "key 옵션으로 특정 메모리를 검색한다", %{agent: agent} do
      {:ok, _} = MemoryManager.store(agent.id, :learned_pattern, "key1", %{a: 1})
      {:ok, _} = MemoryManager.store(agent.id, :learned_pattern, "key2", %{b: 2})

      memories = MemoryManager.retrieve(agent.id, :learned_pattern, key: "key1")

      assert length(memories) == 1
      assert hd(memories).key == "key1"
    end

    test "limit 옵션으로 결과 개수를 제한한다", %{agent: agent} do
      for i <- 1..5 do
        {:ok, _} = MemoryManager.store(agent.id, :learned_pattern, "key_#{i}", %{i: i})
      end

      memories = MemoryManager.retrieve(agent.id, :learned_pattern, limit: 3)

      assert length(memories) == 3
    end

    test "min_relevance 옵션으로 최소 관련성 점수를 필터링한다", %{agent: agent} do
      {:ok, _} = MemoryManager.store(agent.id, :learned_pattern, "low", %{}, relevance_score: 0.3)
      {:ok, _} = MemoryManager.store(agent.id, :learned_pattern, "mid", %{}, relevance_score: 0.6)

      {:ok, _} =
        MemoryManager.store(agent.id, :learned_pattern, "high", %{}, relevance_score: 0.9)

      memories = MemoryManager.retrieve(agent.id, :learned_pattern, min_relevance: 0.5)

      assert length(memories) == 2
      assert Enum.all?(memories, fn m -> m.relevance_score >= 0.5 end)
    end

    test "관련성 점수 내림차순으로 정렬된다", %{agent: agent} do
      {:ok, _} = MemoryManager.store(agent.id, :learned_pattern, "low", %{}, relevance_score: 0.3)

      {:ok, _} =
        MemoryManager.store(agent.id, :learned_pattern, "high", %{}, relevance_score: 0.9)

      {:ok, _} = MemoryManager.store(agent.id, :learned_pattern, "mid", %{}, relevance_score: 0.6)

      memories = MemoryManager.retrieve(agent.id, :learned_pattern)

      scores = Enum.map(memories, & &1.relevance_score)
      assert scores == Enum.sort(scores, :desc)
    end

    test "만료된 메모리를 필터링한다", %{agent: agent} do
      # 이미 만료된 메모리
      past = DateTime.add(DateTime.utc_now(), -3600, :second)
      {:ok, _} = MemoryManager.store(agent.id, :learned_pattern, "expired", %{}, expires_at: past)

      # 아직 만료되지 않은 메모리
      future = DateTime.add(DateTime.utc_now(), 3600, :second)
      {:ok, _} = MemoryManager.store(agent.id, :learned_pattern, "valid", %{}, expires_at: future)

      # 만료 시간이 없는 메모리
      {:ok, _} = MemoryManager.store(agent.id, :learned_pattern, "no_expiry", %{})

      memories = MemoryManager.retrieve(agent.id, :learned_pattern)

      keys = Enum.map(memories, & &1.key)
      assert "expired" not in keys
      assert "valid" in keys
      assert "no_expiry" in keys
    end

    test "conversation_id로 필터링한다", %{agent: agent} do
      conv1 = conversation_fixture()
      conv2 = conversation_fixture()

      {:ok, _} =
        MemoryManager.store(agent.id, :conversation_summary, "s1", %{}, conversation_id: conv1.id)

      {:ok, _} =
        MemoryManager.store(agent.id, :conversation_summary, "s2", %{}, conversation_id: conv2.id)

      memories =
        MemoryManager.retrieve(agent.id, :conversation_summary, conversation_id: conv1.id)

      assert length(memories) == 1
      assert hd(memories).key == "s1"
    end
  end

  describe "list_by_type/2" do
    test "특정 타입의 모든 메모리를 조회한다", %{agent: agent} do
      {:ok, _} = MemoryManager.store(agent.id, :project_context, "ctx1", %{})
      {:ok, _} = MemoryManager.store(agent.id, :project_context, "ctx2", %{})

      memories = MemoryManager.list_by_type(agent.id, :project_context)

      assert length(memories) == 2
    end
  end

  describe "delete/3" do
    test "메모리를 삭제한다", %{agent: agent} do
      {:ok, memory} = MemoryManager.store(agent.id, :learned_pattern, "to_delete", %{})

      assert {:ok, deleted} = MemoryManager.delete(agent.id, :learned_pattern, "to_delete")
      assert deleted.id == memory.id

      # 삭제 확인
      memories = MemoryManager.retrieve(agent.id, :learned_pattern, key: "to_delete")
      assert Enum.empty?(memories)
    end

    test "존재하지 않는 메모리 삭제 시 에러를 반환한다", %{agent: agent} do
      assert {:error, :not_found} =
               MemoryManager.delete(agent.id, :learned_pattern, "nonexistent")
    end
  end

  describe "export_to_markdown/1" do
    setup %{agent: agent} do
      # 테스트용 메모리 저장
      {:ok, _} =
        MemoryManager.store(agent.id, :learned_pattern, "pattern1", %{rule: "test"},
          relevance_score: 0.8
        )

      {:ok, _} = MemoryManager.store(agent.id, :project_context, "context1", %{name: "project"})

      on_exit(fn ->
        # 테스트 후 생성된 파일 정리
        File.rm_rf!("data/memories/#{agent.name}")
      end)

      :ok
    end

    test "Markdown 파일로 메모리를 내보낸다", %{agent: agent} do
      assert {:ok, file_path} = MemoryManager.export_to_markdown(agent.id)

      assert File.exists?(file_path)

      content = File.read!(file_path)
      assert content =~ "# Supervisor Memory: #{agent.name}"
      assert content =~ "## Learned Patterns"
      assert content =~ "pattern1"
      assert content =~ "## Project Context"
      assert content =~ "context1"
    end

    test "존재하지 않는 agent_id에서 에러를 반환한다" do
      fake_id = Ecto.UUID.generate()
      assert {:error, :agent_not_found} = MemoryManager.export_to_markdown(fake_id)
    end
  end

  describe "import_from_markdown/2" do
    setup %{agent: agent} do
      test_dir = "data/memories/#{agent.name}"
      File.mkdir_p!(test_dir)

      on_exit(fn -> File.rm_rf!(test_dir) end)

      %{test_dir: test_dir}
    end

    test "Markdown 파일에서 메모리를 가져온다", %{agent: agent, test_dir: test_dir} do
      content = """
      # Supervisor Memory: #{agent.name}

      ## Learned Patterns

      ### imported_pattern

      - **key**: value
      - **another**: data

      ## Project Context

      ### imported_context

      Some project context here.
      """

      file_path = Path.join(test_dir, "memory.md")
      File.write!(file_path, content)

      assert {:ok, _results} = MemoryManager.import_from_markdown(agent.id, file_path)

      # 가져온 메모리 확인
      patterns = MemoryManager.retrieve(agent.id, :learned_pattern)
      contexts = MemoryManager.retrieve(agent.id, :project_context)

      imported_keys = (patterns ++ contexts) |> Enum.map(& &1.key)
      assert "imported_pattern" in imported_keys or "imported_context" in imported_keys
    end

    test "존재하지 않는 agent_id에서 에러를 반환한다" do
      fake_id = Ecto.UUID.generate()
      assert {:error, :agent_not_found} = MemoryManager.import_from_markdown(fake_id)
    end

    @tag :capture_log
    test "존재하지 않는 파일에서 에러를 반환한다", %{agent: agent} do
      assert {:error, :enoent} =
               MemoryManager.import_from_markdown(agent.id, "/nonexistent/path.md")
    end
  end

  describe "memory types" do
    test "conversation_summary 타입을 저장하고 검색한다", %{agent: agent} do
      {:ok, _} = MemoryManager.store(agent.id, :conversation_summary, "conv1", %{summary: "Test"})
      memories = MemoryManager.retrieve(agent.id, :conversation_summary)
      assert length(memories) == 1
      assert hd(memories).memory_type == :conversation_summary
    end

    test "performance_metric 타입을 저장하고 검색한다", %{agent: agent} do
      {:ok, _} = MemoryManager.store(agent.id, :performance_metric, "metric1", %{duration: 100})
      memories = MemoryManager.retrieve(agent.id, :performance_metric)
      assert length(memories) == 1
      assert hd(memories).memory_type == :performance_metric
    end
  end
end
