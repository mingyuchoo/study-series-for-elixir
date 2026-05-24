defmodule AgenticAiAgent.Agent.WorkflowTest do
  use ExUnit.Case, async: true

  alias AgenticAiAgent.Agent.Workflow
  alias AgenticAiAgent.Design.{AgenticCard, WorkflowGraph}

  describe "from_card/1" do
    test "returns the default ReAct graph when card is nil" do
      wf = Workflow.from_card(nil)
      assert wf.name == "default_react_loop"
      assert "planning" in Map.get(wf.transitions, "idle", [])
      refute Workflow.enforce?(wf)
    end

    test "returns the default ReAct graph when the card has no workflow_graphs" do
      card = %AgenticCard{workflow_graphs: []}
      wf = Workflow.from_card(card)
      assert wf.name == "default_react_loop"
    end

    test "uses the first attached workflow_graph and reads its enforce flag" do
      graph = %WorkflowGraph{
        name: "strict",
        enforce: true,
        transitions: %{"idle" => ["planning"]},
        terminal_states: ["done"],
        approval_points: [],
        allowed_actions: %{"acting" => ["calculator"]},
        required_evidence: %{}
      }

      wf = Workflow.from_card(%AgenticCard{workflow_graphs: [graph]})
      assert wf.name == "strict"
      assert Workflow.enforce?(wf)
      assert "done" in wf.terminal_states
      # cancelled / failed are always added as unconditional terminals.
      assert "failed" in wf.terminal_states
      assert "cancelled" in wf.terminal_states
    end
  end

  describe "validate/3" do
    setup do
      {:ok, wf: Workflow.default()}
    end

    test "allows declared edges", %{wf: wf} do
      assert :ok = Workflow.validate(wf, "idle", "planning")
      assert :ok = Workflow.validate(wf, "planning", "acting")
      assert :ok = Workflow.validate(wf, "acting", "awaiting_approval")
    end

    test "rejects undeclared edges", %{wf: wf} do
      assert {:error, {:invalid_transition, "idle", "acting"}} =
               Workflow.validate(wf, "idle", "acting")
    end

    test "always allows failed and cancelled regardless of source", %{wf: wf} do
      assert :ok = Workflow.validate(wf, "idle", "failed")
      assert :ok = Workflow.validate(wf, "planning", "cancelled")
    end

    test "self-loops are permitted (no spurious failure on repeated state)", %{wf: wf} do
      assert :ok = Workflow.validate(wf, "acting", "acting")
    end

    test "transitions from an unknown source are not blocked", %{wf: wf} do
      # During bootstrap / before the first push_status we may not have a
      # source state at all. The validator should not trip in that case.
      assert :ok = Workflow.validate(wf, "ghost_state", "planning")
    end
  end

  describe "terminal? / approval_point?" do
    test "default graph terminals are done, failed, cancelled" do
      wf = Workflow.default()
      assert Workflow.terminal?(wf, "done")
      assert Workflow.terminal?(wf, "failed")
      assert Workflow.terminal?(wf, "cancelled")
      refute Workflow.terminal?(wf, "planning")
    end

    test "approval points reflect the graph" do
      wf = Workflow.default()
      assert Workflow.approval_point?(wf, "awaiting_approval")
      refute Workflow.approval_point?(wf, "planning")
    end
  end

  describe "tool_allowed_in?/3" do
    test "missing state entry → no restriction" do
      wf = %Workflow{allowed_actions: %{}}
      assert Workflow.tool_allowed_in?(wf, "acting", "python_exec")
    end

    test "state listed → only listed tools allowed" do
      wf = %Workflow{allowed_actions: %{"acting" => ["calculator", "web_search"]}}
      assert Workflow.tool_allowed_in?(wf, "acting", "calculator")
      refute Workflow.tool_allowed_in?(wf, "acting", "python_exec")
    end

    test "wildcard '*' allows any tool" do
      wf = %Workflow{allowed_actions: %{"acting" => ["*"]}}
      assert Workflow.tool_allowed_in?(wf, "acting", "python_exec")
    end

    test "atom states are coerced to string" do
      wf = %Workflow{allowed_actions: %{"acting" => ["calculator"]}}
      assert Workflow.tool_allowed_in?(wf, :acting, "calculator")
      refute Workflow.tool_allowed_in?(wf, :acting, "python_exec")
    end
  end
end
