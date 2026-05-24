defmodule AgenticAiAgent.SafetyTest do
  use ExUnit.Case, async: true

  alias AgenticAiAgent.Safety

  defp baseline_yaml do
    """
    slug: default
    name: Test
    safety_policy:
      human_approval_required_for: [high, medium]
    tool_policy:
      allow: [calculator, web_search]
      deny: [python_exec]
    output_contract:
      cite_sources: true
    workflow_graphs:
      - name: react
        allowed_actions:
          acting: [web_search, calculator]
    """
  end

  defp yaml_minus(yaml, pattern, replacement) do
    String.replace(yaml, pattern, replacement)
  end

  # ----- Clean pass -----

  describe "pass — proposal that doesn't loosen anything" do
    test "verdict :pass for identical body" do
      assert {:ok, %{verdict: :pass, violations: [], score: 1.0}} =
               Safety.audit_card(baseline_yaml(), baseline_yaml())
    end

    test "verdict :pass when proposal only adds a new safe field (e.g. extra task_taxonomy)" do
      extra =
        baseline_yaml() <>
          """
          task_taxonomies:
            - task_type: math
              risk_level: low
              required_tools: [calculator]
              success_criteria: correct
          """

      assert {:ok, %{verdict: :pass}} = Safety.audit_card(baseline_yaml(), extra)
    end
  end

  # ----- Rule: approval_removed_for_high -----

  describe "approval_removed_for_high" do
    test "drops 'high' from human_approval_required_for → fail" do
      proposed =
        yaml_minus(
          baseline_yaml(),
          "human_approval_required_for: [high, medium]",
          "human_approval_required_for: [medium]"
        )

      assert {:ok, %{verdict: :fail, violations: violations}} =
               Safety.audit_card(baseline_yaml(), proposed)

      assert Enum.any?(violations, &(&1.rule == "approval_removed_for_high"))
    end
  end

  # ----- Rule: deny_list_shrunk -----

  describe "deny_list_shrunk" do
    test "removes python_exec from deny → fail" do
      proposed =
        yaml_minus(baseline_yaml(), "deny: [python_exec]", "deny: []")

      assert {:ok, %{verdict: :fail, violations: violations}} =
               Safety.audit_card(baseline_yaml(), proposed)

      assert Enum.any?(violations, &(&1.rule == "deny_list_shrunk"))
    end
  end

  # ----- Rule: high_risk_tool_added -----

  describe "high_risk_tool_added" do
    test "adds python_exec to allow → fail" do
      proposed =
        yaml_minus(
          baseline_yaml(),
          "allow: [calculator, web_search]",
          "allow: [calculator, web_search, python_exec]"
        )

      assert {:ok, %{verdict: :fail, violations: violations}} =
               Safety.audit_card(baseline_yaml(), proposed)

      assert Enum.any?(violations, &(&1.rule == "high_risk_tool_added"))
    end
  end

  # ----- Rule: workflow_acting_widened -----

  describe "workflow_acting_widened" do
    test "widens acting to wildcard → fail" do
      proposed =
        yaml_minus(
          baseline_yaml(),
          "acting: [web_search, calculator]",
          "acting: [\"*\"]"
        )

      assert {:ok, %{verdict: :fail, violations: violations}} =
               Safety.audit_card(baseline_yaml(), proposed)

      assert Enum.any?(violations, &(&1.rule == "workflow_acting_widened"))
    end
  end

  # ----- Rule: output_contract_regressed (warn-only) -----

  describe "output_contract_regressed" do
    test "turns off cite_sources → warn (not fail)" do
      proposed =
        yaml_minus(baseline_yaml(), "cite_sources: true", "cite_sources: false")

      assert {:ok, %{verdict: :warn, violations: [], warnings: warnings}} =
               Safety.audit_card(baseline_yaml(), proposed)

      assert Enum.any?(warnings, &(&1.rule == "output_contract_regressed"))
    end
  end

  # ----- Bad input -----

  describe "robustness" do
    test "unparseable YAML returns a warn verdict instead of crashing" do
      assert {:ok, %{verdict: :warn, warnings: warnings}} =
               Safety.audit_card("not: valid: yaml: at: all", baseline_yaml())

      assert Enum.any?(warnings, &(&1.rule == "parse_failure"))
    end

    test "nil inputs default to empty maps" do
      assert {:ok, %{verdict: :pass}} = Safety.audit_card(nil, nil)
    end
  end
end
