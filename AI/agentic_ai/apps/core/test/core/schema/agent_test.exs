defmodule Core.Schema.AgentTest do
  use Core.DataCase, async: false

  alias Core.Schema.Agent

  describe "changeset/2" do
    test "유효한 속성으로 changeset을 생성한다" do
      attrs = %{
        type: :worker,
        name: "test_agent",
        display_name: "Test Agent",
        description: "A test agent"
      }

      changeset = Agent.changeset(%Agent{}, attrs)

      assert changeset.valid?
    end

    test "type과 name은 필수이다" do
      changeset = Agent.changeset(%Agent{}, %{})

      refute changeset.valid?
      assert errors_on(changeset)[:type]
      assert errors_on(changeset)[:name]
    end

    test "type은 supervisor 또는 worker여야 한다" do
      for type <- [:supervisor, :worker] do
        changeset = Agent.changeset(%Agent{}, %{type: type, name: "test"})
        assert changeset.valid?, "Type #{type} should be valid"
      end
    end

    test "status는 active 또는 disabled여야 한다" do
      for status <- [:active, :disabled] do
        changeset = Agent.changeset(%Agent{}, %{type: :worker, name: "test", status: status})
        assert changeset.valid?, "Status #{status} should be valid"
      end
    end

    test "temperature는 0.0 이상 2.0 이하여야 한다" do
      # 유효한 범위
      for temp <- [0.0, 1.0, 2.0] do
        changeset = Agent.changeset(%Agent{}, %{type: :worker, name: "test", temperature: temp})
        assert changeset.valid?, "Temperature #{temp} should be valid"
      end

      # 유효하지 않은 범위
      for temp <- [-0.1, 2.1, 3.0] do
        changeset = Agent.changeset(%Agent{}, %{type: :worker, name: "test", temperature: temp})
        refute changeset.valid?, "Temperature #{temp} should be invalid"
        assert errors_on(changeset)[:temperature]
      end
    end

    test "max_iterations는 0보다 커야 한다" do
      # 유효한 값
      changeset = Agent.changeset(%Agent{}, %{type: :worker, name: "test", max_iterations: 1})
      assert changeset.valid?

      # 유효하지 않은 값
      for iter <- [0, -1] do
        changeset =
          Agent.changeset(%Agent{}, %{type: :worker, name: "test", max_iterations: iter})

        refute changeset.valid?, "max_iterations #{iter} should be invalid"
        assert errors_on(changeset)[:max_iterations]
      end
    end

    test "기본값이 올바르게 설정된다" do
      agent = %Agent{}

      assert agent.model == "gpt-5-mini"
      assert agent.temperature == 1.0
      assert agent.max_iterations == 10
      assert agent.enabled_tools == []
      assert agent.config == %{}
      assert agent.status == :active
      assert agent.created_from_markdown == false
    end

    test "enabled_tools는 문자열 배열이다" do
      attrs = %{
        type: :worker,
        name: "test",
        enabled_tools: ["calculator", "web_search", "code_executor"]
      }

      changeset = Agent.changeset(%Agent{}, attrs)

      assert changeset.valid?

      assert Ecto.Changeset.get_change(changeset, :enabled_tools) == [
               "calculator",
               "web_search",
               "code_executor"
             ]
    end

    test "config는 맵이다" do
      attrs = %{
        type: :worker,
        name: "test",
        config: %{"max_tasks" => 5, "timeout" => 30}
      }

      changeset = Agent.changeset(%Agent{}, attrs)

      assert changeset.valid?
    end

    test "name은 고유해야 한다" do
      # 첫 번째 에이전트 생성
      {:ok, _} =
        %Agent{}
        |> Agent.changeset(%{type: :worker, name: "unique_name"})
        |> Repo.insert()

      # 같은 이름으로 두 번째 에이전트 생성 시도
      changeset =
        %Agent{}
        |> Agent.changeset(%{type: :worker, name: "unique_name"})

      assert {:error, changeset} = Repo.insert(changeset)
      assert errors_on(changeset)[:name]
    end

    test "모든 선택적 필드를 업데이트할 수 있다" do
      attrs = %{
        type: :supervisor,
        name: "full_agent",
        display_name: "Full Agent",
        description: "A fully configured agent",
        system_prompt: "You are a helpful assistant",
        model: "gpt-4",
        temperature: 0.7,
        max_iterations: 15,
        enabled_tools: ["calculator"],
        config: %{"key" => "value"},
        status: :active,
        created_from_markdown: true,
        markdown_path: "/path/to/file.md"
      }

      changeset = Agent.changeset(%Agent{}, attrs)

      assert changeset.valid?
    end
  end
end
