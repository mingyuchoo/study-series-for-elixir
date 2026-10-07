defmodule AgentDomainTest do
  use ExUnit.Case, async: true

  alias AgentDomain.{Calculator, ChatProtocol, ConfigParser, GroupChatText, RagText, RoutingRules, TaskRouter, ToolPolicy}

  test "routing selects a worker from supplied data without a database" do
    rules = RoutingRules.default_rules() |> RoutingRules.build_rule_index()
    workers = [
      %{name: "general_worker", description: "", enabled_tools: []},
      %{name: "calculator_worker", description: "수학 계산", enabled_tools: ["calculate"]}
    ]

    assert {:ok, %{name: "calculator_worker"}, score} =
             TaskRouter.select_worker_with_score("2 + 2 계산", workers, rules)

    assert score > 0
    assert {:error, :no_workers_available} = TaskRouter.select_worker("anything", [], rules)
  end

  test "markdown parsing produces agent attributes without reading a file" do
    markdown = """
    ---
    type: worker
    name: calculator_worker
    temperature: 0.5
    ---
    ## System Prompt
    Calculate accurately.

    ## Configuration
    {"max_concurrent_tasks": 2}

    ## Enabled Tools
    - calculate
    """

    assert {:ok, frontmatter, body} = ConfigParser.parse_markdown(markdown)
    assert {:ok, attrs} = ConfigParser.build_agent_attrs(frontmatter, body, "agent.md")
    assert attrs.name == "calculator_worker"
    assert attrs.temperature == 0.5
    assert attrs.enabled_tools == ["calculate"]
    assert attrs.config == %{"max_concurrent_tasks" => 2}
  end

  test "restricted tools are rejected by the pure policy" do
    assert :ok = ToolPolicy.authorize("calculate", allowed_tools: ["calculate"])
    assert {:error, :tool_requires_approval} =
             ToolPolicy.authorize("write_file", allowed_tools: ["write_file"])
  end

  test "calculator evaluates arithmetic without a tool registry" do
    assert {:ok, 20} = Calculator.evaluate("(2 + 3) * 4")
    assert {:error, "Division by zero"} = Calculator.evaluate("3 / 0")
  end

  test "RAG text preparation and fusion require no storage or embedding service" do
    assert ["hello world"] = RagText.chunk_text(" hello   world ")
    assert length(RagText.embed_text("hello world")) == 384

    result = %{rag_id: "rag", position: 0, content: "hello"}
    assert [%{score: score}] = RagText.fuse_results([result], [result])
    assert score > 1 / 61
  end

  test "group chat transcript and moderator response are parsed from values" do
    transcript = GroupChatText.restore_transcript(%{"entries" => [%{"kind" => "worker", "round" => 1, "display_name" => "Calc", "content" => "4"}]})
    assert "라운드 1 [Calc]: 4" = GroupChatText.format_transcript_for_moderator(transcript)

    assert {:ok, %{decision: "final", final_answer: "4"}} =
             GroupChatText.parse_moderator_output("```json\n{\"decision\":\"final\",\"final_answer\":\"4\"}\n```")
  end

  test "streamed tool-call arguments are assembled without network access" do
    first = ChatProtocol.merge_tool_call_delta(nil, %{"id" => "call-1", "function" => %{"name" => "calculate", "arguments" => "{\"x\":"}})
    result = ChatProtocol.merge_tool_call_delta(first, %{"function" => %{"arguments" => "2}"}})

    assert result["function"]["arguments"] == "{\"x\":2}"
    assert [%{role: "assistant", content: "hello"}] =
             ChatProtocol.format_messages_for_api([%{role: "assistant", content: "hello"}])
  end
end
