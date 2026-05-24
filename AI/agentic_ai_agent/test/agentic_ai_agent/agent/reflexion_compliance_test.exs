defmodule AgenticAiAgent.Agent.ReflexionComplianceTest do
  use ExUnit.Case, async: true

  alias AgenticAiAgent.Agent.ReflexionCompliance

  # ----- check_themes/2 -----

  describe "check_themes/2" do
    test ":ok for empty history" do
      assert :ok = ReflexionCompliance.check_themes([])
    end

    test ":ok when the head theme is nil (no signal)" do
      assert :ok = ReflexionCompliance.check_themes([nil, "missing_retrieve"])
    end

    test ":ok when only one critique with the same theme so far" do
      # threshold default 2 → one same-theme is not enough.
      # Wait — default threshold IS 2, so one same-theme already crosses?
      # Actually the doc says "≥ threshold". Let's verify with explicit
      # threshold=3 to see the gating clearly first.
      assert :ok = ReflexionCompliance.check_themes(["a"], 3)
      assert :ok = ReflexionCompliance.check_themes(["a", "a"], 3)
    end

    test "escalates when consecutive same-theme prefix meets threshold" do
      assert {:escalate, "missing_retrieve", 2} =
               ReflexionCompliance.check_themes(["missing_retrieve", "missing_retrieve"])
    end

    test "does NOT escalate when the streak breaks earlier in history" do
      # `["missing_retrieve", "tool_misuse", "missing_retrieve"]` —
      # head streak length = 1, NOT escalation.
      assert :ok =
               ReflexionCompliance.check_themes([
                 "missing_retrieve",
                 "tool_misuse",
                 "missing_retrieve"
               ])
    end

    test "counts streak length correctly past threshold" do
      assert {:escalate, "missing_retrieve", 4} =
               ReflexionCompliance.check_themes([
                 "missing_retrieve",
                 "missing_retrieve",
                 "missing_retrieve",
                 "missing_retrieve"
               ])
    end

    test "custom threshold honored" do
      # threshold=3 — two same-theme aren't enough.
      assert :ok = ReflexionCompliance.check_themes(["a", "a"], 3)
      assert {:escalate, "a", 3} = ReflexionCompliance.check_themes(["a", "a", "a"], 3)
    end
  end

  # ----- escalation_system_message/2 -----

  describe "escalation_system_message/2" do
    test "returns nil for a nil theme" do
      assert ReflexionCompliance.escalation_system_message(nil, 3) == nil
    end

    test "returns a system-role message naming the theme and count" do
      msg = ReflexionCompliance.escalation_system_message("missing_retrieve", 3)

      assert %{"role" => "system", "content" => content} = msg
      assert content =~ "ESCALATED"
      assert content =~ "missing_retrieve"
      assert content =~ "3"
      assert content =~ "DIFFERENT action"
    end
  end

  # ----- outcome_for_persist/3 -----

  describe "outcome_for_persist/3" do
    test "escalated when the run ever escalated" do
      assert "escalated" = ReflexionCompliance.outcome_for_persist(5, true, true)
      # Even count=0 + escalated stays escalated (escalation is sticky).
      assert "escalated" = ReflexionCompliance.outcome_for_persist(0, true, true)
    end

    test "nil when no critique was ever produced" do
      assert nil == ReflexionCompliance.outcome_for_persist(0, false, false)
    end

    test "complied when count=0 + no escalation + a critique fired" do
      assert "complied" = ReflexionCompliance.outcome_for_persist(0, false, true)
    end

    test "ignored when count>0 but no escalation" do
      assert "ignored" = ReflexionCompliance.outcome_for_persist(1, false, true)
    end
  end
end
