defmodule Core.Agent.ConfigLoaderTest do
  use Core.DataCase, async: false

  alias Core.Agent.ConfigLoader

  describe "parse_frontmatter/1" do
    test "YAML-like frontmatter를 올바르게 파싱한다" do
      frontmatter = """
      type: supervisor
      name: main_supervisor
      model: gpt-5-mini
      temperature: 0.7
      max_iterations: 15
      """

      result = ConfigLoader.parse_frontmatter(frontmatter)

      assert result["type"] == "supervisor"
      assert result["name"] == "main_supervisor"
      assert result["model"] == "gpt-5-mini"
      assert result["temperature"] == 0.7
      assert result["max_iterations"] == 15
    end

    test "정수 값을 올바르게 파싱한다" do
      result = ConfigLoader.parse_frontmatter("count: 42")
      assert result["count"] == 42
    end

    test "실수 값을 올바르게 파싱한다" do
      result = ConfigLoader.parse_frontmatter("ratio: 3.14")
      assert result["ratio"] == 3.14
    end

    test "불리언 값을 올바르게 파싱한다" do
      result = ConfigLoader.parse_frontmatter("enabled: true\ndisabled: false")
      assert result["enabled"] == true
      assert result["disabled"] == false
    end

    test "문자열 값을 그대로 유지한다" do
      result = ConfigLoader.parse_frontmatter("description: This is a test")
      assert result["description"] == "This is a test"
    end

    test "빈 줄을 무시한다" do
      frontmatter = """
      key1: value1

      key2: value2
      """

      result = ConfigLoader.parse_frontmatter(frontmatter)
      assert result["key1"] == "value1"
      assert result["key2"] == "value2"
    end

    test "콜론이 없는 줄을 무시한다" do
      frontmatter = """
      key1: value1
      invalid line without colon
      key2: value2
      """

      result = ConfigLoader.parse_frontmatter(frontmatter)
      assert result["key1"] == "value1"
      assert result["key2"] == "value2"
      refute Map.has_key?(result, "invalid line without colon")
    end
  end

  describe "parse_markdown/1" do
    test "유효한 Markdown 형식을 frontmatter와 body로 분리한다" do
      content = """
      ---
      type: worker
      name: test_agent
      ---

      # Test Agent

      ## System Prompt
      You are a test assistant.
      """

      {:ok, frontmatter, body} = ConfigLoader.parse_markdown(content)

      assert frontmatter["type"] == "worker"
      assert frontmatter["name"] == "test_agent"
      assert String.contains?(body, "System Prompt")
      assert String.contains?(body, "You are a test assistant.")
    end

    test "frontmatter가 없는 경우 에러를 반환한다" do
      content = """
      # No Frontmatter

      Just content without frontmatter.
      """

      assert {:error, "Invalid markdown format: frontmatter not found"} =
               ConfigLoader.parse_markdown(content)
    end

    test "잘못된 frontmatter 형식에서 에러를 반환한다" do
      content = "---\ntype: worker"

      assert {:error, "Invalid markdown format: frontmatter not found"} =
               ConfigLoader.parse_markdown(content)
    end
  end

  describe "parse_body/1" do
    test "System Prompt 섹션을 추출한다" do
      body = """
      # Agent

      ## System Prompt
      You are a helpful assistant.
      Always respond in Korean.

      ## Other Section
      Other content.
      """

      result = ConfigLoader.parse_body(body)

      assert result["system_prompt"] =~ "You are a helpful assistant."
      assert result["system_prompt"] =~ "Always respond in Korean."
    end

    test "Configuration 섹션의 JSON을 파싱한다" do
      body = """
      ## Configuration
      {"max_concurrent_tasks": 5, "retry_count": 3}

      ## Other
      Content
      """

      result = ConfigLoader.parse_body(body)

      assert result["config"]["max_concurrent_tasks"] == 5
      assert result["config"]["retry_count"] == 3
    end

    test "Enabled Tools 리스트를 파싱한다" do
      body = """
      ## Enabled Tools
      - calculator
      - web_search
      - code_executor
      """

      result = ConfigLoader.parse_body(body)

      assert result["enabled_tools"] == ["calculator", "web_search", "code_executor"]
    end

    test "모든 섹션이 없어도 기본값을 반환한다" do
      result = ConfigLoader.parse_body("Just some text")

      assert result["system_prompt"] == nil
      assert result["config"] == nil
      assert result["enabled_tools"] == []
    end

    test "잘못된 JSON Configuration은 빈 맵을 반환한다" do
      body = """
      ## Configuration
      invalid json here
      """

      result = ConfigLoader.parse_body(body)
      assert result["config"] == %{}
    end
  end

  describe "build_agent_attrs/3" do
    test "frontmatter와 body를 결합하여 Agent 속성을 생성한다" do
      frontmatter = %{
        "type" => "supervisor",
        "name" => "test_supervisor",
        "display_name" => "Test Supervisor",
        "model" => "gpt-5-mini",
        "temperature" => 0.7
      }

      body = """
      ## System Prompt
      Test prompt

      ## Enabled Tools
      - calculator
      """

      {:ok, attrs} = ConfigLoader.build_agent_attrs(frontmatter, body, "/path/to/file.md")

      assert attrs.type == :supervisor
      assert attrs.name == "test_supervisor"
      assert attrs.display_name == "Test Supervisor"
      assert attrs.model == "gpt-5-mini"
      assert attrs.temperature == 0.7
      assert attrs.system_prompt =~ "Test prompt"
      assert attrs.enabled_tools == ["calculator"]
      assert attrs.created_from_markdown == true
      assert attrs.markdown_path == "/path/to/file.md"
    end

    test "type이 supervisor일 때 :supervisor atom으로 변환한다" do
      frontmatter = %{"type" => "supervisor", "name" => "test"}
      {:ok, attrs} = ConfigLoader.build_agent_attrs(frontmatter, "", "/test.md")
      assert attrs.type == :supervisor
    end

    test "type이 worker일 때 :worker atom으로 변환한다" do
      frontmatter = %{"type" => "worker", "name" => "test"}
      {:ok, attrs} = ConfigLoader.build_agent_attrs(frontmatter, "", "/test.md")
      assert attrs.type == :worker
    end

    test "알 수 없는 type은 :worker로 기본 설정한다" do
      frontmatter = %{"type" => "unknown", "name" => "test"}
      {:ok, attrs} = ConfigLoader.build_agent_attrs(frontmatter, "", "/test.md")
      assert attrs.type == :worker
    end

    test "name이 없으면 에러를 반환한다" do
      frontmatter = %{"type" => "worker"}

      assert {:error, "name is required in frontmatter"} =
               ConfigLoader.build_agent_attrs(frontmatter, "", "/test.md")
    end

    test "기본값이 올바르게 설정된다" do
      frontmatter = %{"name" => "test"}
      {:ok, attrs} = ConfigLoader.build_agent_attrs(frontmatter, "", "/test.md")

      assert attrs.model == "gpt-5-mini"
      assert attrs.temperature == 1.0
      assert attrs.max_iterations == 10
      assert attrs.config == %{}
      assert attrs.status == :active
    end
  end

  describe "upsert_agent/1" do
    test "새로운 에이전트를 생성한다" do
      attrs = %{
        type: :worker,
        name: "new_test_agent_#{System.unique_integer([:positive])}",
        display_name: "New Agent",
        model: "gpt-5-mini"
      }

      assert {:ok, agent} = ConfigLoader.upsert_agent(attrs)
      assert agent.name == attrs.name
      assert agent.display_name == "New Agent"
    end

    test "기존 에이전트를 업데이트한다" do
      # 먼저 에이전트 생성
      attrs = %{
        type: :worker,
        name: "existing_agent_#{System.unique_integer([:positive])}",
        display_name: "Original Name",
        model: "gpt-5-mini"
      }

      {:ok, original} = ConfigLoader.upsert_agent(attrs)

      # 같은 이름으로 업데이트
      updated_attrs = %{attrs | display_name: "Updated Name"}
      {:ok, updated} = ConfigLoader.upsert_agent(updated_attrs)

      assert updated.id == original.id
      assert updated.display_name == "Updated Name"
    end
  end

  describe "load_config/1" do
    setup do
      # 테스트용 임시 디렉토리 및 파일 생성
      test_dir = System.tmp_dir!() |> Path.join("config_loader_test_#{System.unique_integer()}")
      File.mkdir_p!(test_dir)

      on_exit(fn -> File.rm_rf!(test_dir) end)

      %{test_dir: test_dir}
    end

    test "유효한 Markdown 파일을 로드하고 Agent를 생성한다", %{test_dir: test_dir} do
      file_path = Path.join(test_dir, "test_agent.md")

      content = """
      ---
      type: worker
      name: loaded_agent_#{System.unique_integer([:positive])}
      display_name: Loaded Agent
      temperature: 0.5
      ---

      # Test Agent

      ## System Prompt
      You are a helpful assistant.

      ## Enabled Tools
      - calculator
      """

      File.write!(file_path, content)

      assert {:ok, agent} = ConfigLoader.load_config(file_path)
      assert agent.display_name == "Loaded Agent"
      assert agent.temperature == 0.5
      assert agent.system_prompt =~ "You are a helpful assistant."
      assert "calculator" in agent.enabled_tools
    end

    @tag :capture_log
    test "존재하지 않는 파일에서 에러를 반환한다" do
      assert {:error, :enoent} = ConfigLoader.load_config("/nonexistent/path.md")
    end
  end

  describe "load_all_configs/1" do
    setup do
      test_dir = System.tmp_dir!() |> Path.join("config_loader_all_#{System.unique_integer()}")
      File.mkdir_p!(test_dir)

      on_exit(fn -> File.rm_rf!(test_dir) end)

      %{test_dir: test_dir}
    end

    test "디렉토리의 모든 .md 파일을 로드한다", %{test_dir: test_dir} do
      # 두 개의 에이전트 파일 생성
      for i <- 1..2 do
        content = """
        ---
        type: worker
        name: batch_agent_#{System.unique_integer([:positive])}_#{i}
        ---

        ## System Prompt
        Agent #{i}
        """

        File.write!(Path.join(test_dir, "agent_#{i}.md"), content)
      end

      # .md가 아닌 파일도 생성
      File.write!(Path.join(test_dir, "readme.txt"), "Not an agent")

      assert {:ok, agents} = ConfigLoader.load_all_configs(test_dir)
      assert length(agents) == 2
    end

    @tag :capture_log
    test "존재하지 않는 디렉토리에서 에러를 반환한다" do
      assert {:error, _} = ConfigLoader.load_all_configs("/nonexistent/directory")
    end

    test "빈 디렉토리에서 빈 목록을 반환한다", %{test_dir: test_dir} do
      assert {:ok, []} = ConfigLoader.load_all_configs(test_dir)
    end
  end

  describe "restructure_worker 설정 파일" do
    @project_root Path.expand("../../../../..", __DIR__)

    test "restructure_worker.md 파일을 올바르게 파싱한다" do
      file_path = Path.join(@project_root, "config/agents/worker_restructure.md")

      {:ok, content} = File.read(file_path)
      {:ok, frontmatter, body} = ConfigLoader.parse_markdown(content)

      assert frontmatter["type"] == "worker"
      assert frontmatter["name"] == "restructure_worker"
      assert frontmatter["display_name"] == "Restructure Worker"
      assert frontmatter["temperature"] == 0.7
      assert frontmatter["max_iterations"] == 3
    end

    test "restructure_worker의 System Prompt를 추출한다" do
      file_path = Path.join(@project_root, "config/agents/worker_restructure.md")

      {:ok, content} = File.read(file_path)
      {:ok, _frontmatter, body} = ConfigLoader.parse_markdown(content)

      sections = ConfigLoader.parse_body(body)

      assert sections["system_prompt"] =~ "결론 우선 구조로 재구성"
      assert sections["system_prompt"] =~ "핵심 결론"
      assert sections["system_prompt"] =~ "주요 근거"
      assert sections["system_prompt"] =~ "세부 사항"
    end

    test "restructure_worker의 Configuration을 파싱한다" do
      file_path = Path.join(@project_root, "config/agents/worker_restructure.md")

      {:ok, content} = File.read(file_path)
      {:ok, _frontmatter, body} = ConfigLoader.parse_markdown(content)

      sections = ConfigLoader.parse_body(body)

      assert sections["config"]["preserve_original_meaning"] == true
      assert sections["config"]["max_conclusion_sentences"] == 2
      assert sections["config"]["min_supporting_points"] == 2
    end

    test "restructure_worker를 DB에 로드한다" do
      file_path = Path.join(@project_root, "config/agents/worker_restructure.md")

      assert {:ok, agent} = ConfigLoader.load_config(file_path)

      assert agent.name == "restructure_worker"
      assert agent.type == :worker
      assert agent.display_name == "Restructure Worker"
      assert agent.temperature == 0.7
      assert agent.max_iterations == 3
      assert agent.system_prompt =~ "결론 우선 구조"
    end
  end

  describe "emoji_worker 설정 파일" do
    @project_root Path.expand("../../../../..", __DIR__)

    test "emoji_worker.md 파일을 올바르게 파싱한다" do
      file_path = Path.join(@project_root, "config/agents/worker_emoji.md")

      {:ok, content} = File.read(file_path)
      {:ok, frontmatter, body} = ConfigLoader.parse_markdown(content)

      assert frontmatter["type"] == "worker"
      assert frontmatter["name"] == "emoji_worker"
      assert frontmatter["display_name"] == "Emoji Worker"
      assert frontmatter["temperature"] == 0.8
      assert frontmatter["max_iterations"] == 3
    end

    test "emoji_worker의 System Prompt를 추출한다" do
      file_path = Path.join(@project_root, "config/agents/worker_emoji.md")

      {:ok, content} = File.read(file_path)
      {:ok, _frontmatter, body} = ConfigLoader.parse_markdown(content)

      sections = ConfigLoader.parse_body(body)

      assert sections["system_prompt"] =~ "이모지를 추가"
      assert sections["system_prompt"] =~ "가독성"
      assert sections["system_prompt"] =~ "친근감"
    end

    test "emoji_worker의 Configuration을 파싱한다" do
      file_path = Path.join(@project_root, "config/agents/worker_emoji.md")

      {:ok, content} = File.read(file_path)
      {:ok, _frontmatter, body} = ConfigLoader.parse_markdown(content)

      sections = ConfigLoader.parse_body(body)

      assert sections["config"]["emoji_density"] == "moderate"
      assert sections["config"]["prefer_unicode_emoji"] == true
      assert sections["config"]["max_emoji_per_paragraph"] == 3
    end

    test "emoji_worker를 DB에 로드한다" do
      file_path = Path.join(@project_root, "config/agents/worker_emoji.md")

      assert {:ok, agent} = ConfigLoader.load_config(file_path)

      assert agent.name == "emoji_worker"
      assert agent.type == :worker
      assert agent.display_name == "Emoji Worker"
      assert agent.temperature == 0.8
      assert agent.max_iterations == 3
      assert agent.system_prompt =~ "이모지"
    end
  end
end
