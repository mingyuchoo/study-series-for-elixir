defmodule Core.Agent.NewWorkersTest do
  @moduledoc """
  신규 추가된 Worker 에이전트(restructure_worker, emoji_worker)에 대한 테스트입니다.
  """

  use Core.DataCase, async: false

  import Core.Fixtures

  alias Core.Contexts.Agents

  describe "restructure_worker fixture" do
    test "restructure_worker fixture를 생성한다" do
      agent = restructure_worker_fixture()

      assert agent.name =~ "restructure_worker"
      assert agent.type == :worker
      assert agent.display_name == "Restructure Worker"
      assert agent.temperature == 0.7
      assert agent.max_iterations == 3
    end

    test "restructure_worker의 시스템 프롬프트가 올바르다" do
      agent = restructure_worker_fixture()

      assert agent.system_prompt =~ "결론 우선 구조"
      assert agent.system_prompt =~ "핵심 결론"
      assert agent.system_prompt =~ "주요 근거"
      assert agent.system_prompt =~ "세부 사항"
    end

    test "restructure_worker의 config가 올바르다" do
      agent = restructure_worker_fixture()

      assert agent.config["preserve_original_meaning"] == true
      assert agent.config["max_conclusion_sentences"] == 2
      assert agent.config["min_supporting_points"] == 2
    end

    test "restructure_worker에는 enabled_tools가 비어있다" do
      agent = restructure_worker_fixture()

      assert agent.enabled_tools == []
    end

    test "커스텀 속성으로 fixture를 생성할 수 있다" do
      agent = restructure_worker_fixture(%{temperature: 0.5, max_iterations: 5})

      assert agent.temperature == 0.5
      assert agent.max_iterations == 5
    end
  end

  describe "emoji_worker fixture" do
    test "emoji_worker fixture를 생성한다" do
      agent = emoji_worker_fixture()

      assert agent.name =~ "emoji_worker"
      assert agent.type == :worker
      assert agent.display_name == "Emoji Worker"
      assert agent.temperature == 0.8
      assert agent.max_iterations == 3
    end

    test "emoji_worker의 시스템 프롬프트가 올바르다" do
      agent = emoji_worker_fixture()

      assert agent.system_prompt =~ "이모지"
      assert agent.system_prompt =~ "가독성"
      assert agent.system_prompt =~ "친근감"
    end

    test "emoji_worker의 config가 올바르다" do
      agent = emoji_worker_fixture()

      assert agent.config["emoji_density"] == "moderate"
      assert agent.config["prefer_unicode_emoji"] == true
      assert agent.config["max_emoji_per_paragraph"] == 3
    end

    test "emoji_worker에는 enabled_tools가 비어있다" do
      agent = emoji_worker_fixture()

      assert agent.enabled_tools == []
    end

    test "커스텀 속성으로 fixture를 생성할 수 있다" do
      agent = emoji_worker_fixture(%{temperature: 0.5, status: :disabled})

      assert agent.temperature == 0.5
      assert agent.status == :disabled
    end
  end

  describe "Agents context와의 통합" do
    test "list_workers/0에서 restructure_worker를 조회할 수 있다" do
      agent = restructure_worker_fixture(%{status: :active})

      workers = Agents.list_workers()
      worker_ids = Enum.map(workers, & &1.id)

      assert agent.id in worker_ids
    end

    test "list_workers/0에서 emoji_worker를 조회할 수 있다" do
      agent = emoji_worker_fixture(%{status: :active})

      workers = Agents.list_workers()
      worker_ids = Enum.map(workers, & &1.id)

      assert agent.id in worker_ids
    end

    test "get_agent_config/2로 restructure_worker 설정을 조회할 수 있다" do
      agent = restructure_worker_fixture()

      assert Agents.get_agent_config(agent, "preserve_original_meaning") == true
      assert Agents.get_agent_config(agent, "max_conclusion_sentences") == 2
    end

    test "get_agent_config/2로 emoji_worker 설정을 조회할 수 있다" do
      agent = emoji_worker_fixture()

      assert Agents.get_agent_config(agent, "emoji_density") == "moderate"
      assert Agents.get_agent_config(agent, "max_emoji_per_paragraph") == 3
    end

    test "agent_has_tool?/2는 빈 enabled_tools에 대해 false를 반환한다" do
      restructure = restructure_worker_fixture()
      emoji = emoji_worker_fixture()

      refute Agents.agent_has_tool?(restructure, "calculator")
      refute Agents.agent_has_tool?(emoji, "web_search")
    end
  end

  describe "두 에이전트의 조합 사용" do
    test "restructure_worker와 emoji_worker를 함께 생성할 수 있다" do
      restructure = restructure_worker_fixture()
      emoji = emoji_worker_fixture()

      assert restructure.id != emoji.id
      assert restructure.name != emoji.name

      workers = Agents.list_workers()
      worker_ids = Enum.map(workers, & &1.id)

      assert restructure.id in worker_ids
      assert emoji.id in worker_ids
    end

    test "두 에이전트가 다른 temperature 값을 가진다" do
      restructure = restructure_worker_fixture()
      emoji = emoji_worker_fixture()

      assert restructure.temperature == 0.7
      assert emoji.temperature == 0.8
    end

    test "두 에이전트가 다른 설명을 가진다" do
      restructure = restructure_worker_fixture()
      emoji = emoji_worker_fixture()

      assert restructure.description =~ "결론 우선"
      assert emoji.description =~ "이모지"
    end
  end
end
