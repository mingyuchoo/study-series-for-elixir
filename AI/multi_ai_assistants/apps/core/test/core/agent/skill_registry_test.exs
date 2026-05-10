defmodule Core.Agent.SkillRegistryTest do
  use ExUnit.Case, async: false

  alias Core.Agent.SkillRegistry

  # 프로젝트 루트 기준 절대 경로 계산
  @skills_dir Path.join([__DIR__, "..", "..", "..", "..", "..", "config", "skills"])
              |> Path.expand()

  # 테스트용 임시 스킬 디렉토리
  @test_skills_dir Path.join([System.tmp_dir!(), "test_skills_#{:rand.uniform(10000)}"])

  setup do
    # 테스트 전에 스킬을 명시적으로 로드
    {:ok, skills} = SkillRegistry.load_all_skills(@skills_dir)
    {:ok, skills: skills}
  end

  describe "load_all_skills/1" do
    test "스킬 디렉토리에서 모든 스킬을 로드한다", %{skills: skills} do
      assert is_list(skills)
      assert length(skills) >= 2

      skill_names = Enum.map(skills, & &1.name)
      assert "research-report" in skill_names
      assert "code-analysis" in skill_names
    end

    test "존재하지 않는 디렉토리는 빈 리스트를 반환한다" do
      {:ok, skills} = SkillRegistry.load_all_skills("nonexistent/dir")
      assert skills == []
    end
  end

  describe "get_skill/1" do
    test "이름으로 특정 스킬을 조회한다" do
      skill = SkillRegistry.get_skill("research-report")

      assert skill != nil
      assert skill.name == "research-report"
      assert skill.display_name == "Research Report Generator"
      assert is_list(skill.allowed_tools)
      assert "search_web" in skill.allowed_tools
      # 하위 호환성: required_tools도 동일 값
      assert skill.required_tools == skill.allowed_tools
    end

    test "존재하지 않는 스킬은 nil을 반환한다" do
      assert SkillRegistry.get_skill("nonexistent_skill") == nil
    end
  end

  describe "get_available_skills/1" do
    test "enabled_tools에 맞는 스킬만 필터링한다" do
      # research-report는 search_web, write_file 필요
      available = SkillRegistry.get_available_skills(["search_web", "write_file"])

      skill_names = Enum.map(available, & &1.name)
      assert "research-report" in skill_names
    end

    test "필요한 도구가 없으면 해당 스킬은 제외된다" do
      # read_file만 있으면 research-report는 사용 불가 (search_web 없음)
      available = SkillRegistry.get_available_skills(["read_file"])

      skill_names = Enum.map(available, & &1.name)
      refute "research-report" in skill_names
    end

    test "빈 enabled_tools는 빈 리스트를 반환한다" do
      available = SkillRegistry.get_available_skills([])
      assert available == []
    end
  end

  describe "build_skill_prompt/1" do
    test "스킬 목록을 시스템 프롬프트 형태로 변환한다" do
      skill = SkillRegistry.get_skill("research-report")
      prompt = SkillRegistry.build_skill_prompt([skill])

      assert is_binary(prompt)
      assert String.contains?(prompt, "사용 가능한 스킬")
      assert String.contains?(prompt, "Research Report Generator")
      assert String.contains?(prompt, "워크플로우")
    end

    test "빈 스킬 목록은 빈 문자열을 반환한다" do
      prompt = SkillRegistry.build_skill_prompt([])
      assert prompt == ""
    end
  end

  describe "스킬 파일 구조" do
    test "스킬은 올바른 필드를 가진다 (Agent Skills 명세)" do
      skill = SkillRegistry.get_skill("research-report")

      # 필수 필드
      assert Map.has_key?(skill, :name)
      assert Map.has_key?(skill, :description)

      # 선택 필드 (명세)
      assert Map.has_key?(skill, :allowed_tools)
      assert Map.has_key?(skill, :license)
      assert Map.has_key?(skill, :compatibility)

      # 추가 필드 (구현)
      assert Map.has_key?(skill, :display_name)
      assert Map.has_key?(skill, :required_tools)
      assert Map.has_key?(skill, :status)
      assert Map.has_key?(skill, :workflow)
      assert Map.has_key?(skill, :examples)
      assert Map.has_key?(skill, :metadata)
    end

    test "code-analysis 스킬의 allowed-tools를 확인한다" do
      skill = SkillRegistry.get_skill("code-analysis")

      assert skill != nil
      assert "read_file" in skill.allowed_tools
      assert "execute_code" in skill.allowed_tools
    end
  end

  describe "name 검증 (Agent Skills 명세)" do
    setup do
      # 테스트용 임시 디렉토리 생성
      File.rm_rf!(@test_skills_dir)
      File.mkdir_p!(@test_skills_dir)

      on_exit(fn ->
        File.rm_rf!(@test_skills_dir)
      end)

      :ok
    end

    test "유효한 name 형식을 허용한다" do
      create_test_skill("valid-skill", "valid-skill", "A valid skill description")
      {:ok, skills} = SkillRegistry.load_all_skills(@test_skills_dir)

      assert length(skills) == 1
      assert Enum.at(skills, 0).name == "valid-skill"
    end

    test "name이 디렉토리명과 불일치하면 거부한다" do
      create_test_skill("wrong-name", "different-name", "Description")
      {:ok, skills} = SkillRegistry.load_all_skills(@test_skills_dir)

      assert skills == []
    end

    test "대문자를 포함한 name을 거부한다" do
      create_test_skill("Invalid-Name", "Invalid-Name", "Description")
      {:ok, skills} = SkillRegistry.load_all_skills(@test_skills_dir)

      assert skills == []
    end

    test "하이픈으로 시작하는 name을 거부한다" do
      create_test_skill("-invalid", "-invalid", "Description")
      {:ok, skills} = SkillRegistry.load_all_skills(@test_skills_dir)

      assert skills == []
    end

    test "연속 하이픈을 포함한 name을 거부한다" do
      create_test_skill("invalid--name", "invalid--name", "Description")
      {:ok, skills} = SkillRegistry.load_all_skills(@test_skills_dir)

      assert skills == []
    end
  end

  describe "description 검증" do
    setup do
      File.rm_rf!(@test_skills_dir)
      File.mkdir_p!(@test_skills_dir)

      on_exit(fn ->
        File.rm_rf!(@test_skills_dir)
      end)

      :ok
    end

    test "빈 description을 거부한다" do
      create_test_skill("test-skill", "test-skill", "")
      {:ok, skills} = SkillRegistry.load_all_skills(@test_skills_dir)

      assert skills == []
    end

    test "1024자 이하 description을 허용한다" do
      desc = String.duplicate("a", 1024)
      create_test_skill("test-skill", "test-skill", desc)
      {:ok, skills} = SkillRegistry.load_all_skills(@test_skills_dir)

      assert length(skills) == 1
    end

    test "1024자 초과 description을 거부한다" do
      desc = String.duplicate("a", 1025)
      create_test_skill("test-skill", "test-skill", desc)
      {:ok, skills} = SkillRegistry.load_all_skills(@test_skills_dir)

      assert skills == []
    end
  end

  describe "allowed-tools 파싱" do
    setup do
      File.rm_rf!(@test_skills_dir)
      File.mkdir_p!(@test_skills_dir)

      on_exit(fn ->
        File.rm_rf!(@test_skills_dir)
      end)

      :ok
    end

    test "최상위 allowed-tools를 파싱한다" do
      skill_dir = Path.join(@test_skills_dir, "test-skill")
      File.mkdir_p!(skill_dir)

      content = """
      ---
      name: test-skill
      description: Test skill with allowed-tools
      allowed-tools: tool1 tool2 tool3
      ---

      # Test Skill
      """

      File.write!(Path.join(skill_dir, "SKILL.md"), content)

      {:ok, skills} = SkillRegistry.load_all_skills(@test_skills_dir)
      skill = Enum.at(skills, 0)

      assert skill.allowed_tools == ["tool1", "tool2", "tool3"]
    end
  end

  # Helper: 테스트용 스킬 생성
  defp create_test_skill(dir_name, skill_name, description) do
    skill_dir = Path.join(@test_skills_dir, dir_name)
    File.mkdir_p!(skill_dir)

    content = """
    ---
    name: #{skill_name}
    description: #{description}
    ---

    # Test Skill
    """

    File.write!(Path.join(skill_dir, "SKILL.md"), content)
  end
end
