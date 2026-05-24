defmodule AgenticAiAgent.Improver.PatternsTest do
  use AgenticAiAgent.DataCase, async: false

  alias AgenticAiAgent.Improver.{Patterns, Proposal}

  defp applied!(slug, score_delta, opts \\ []) do
    Repo.insert!(%Proposal{
      kind: Keyword.get(opts, :kind, "card_edit"),
      target: slug,
      status: "applied",
      score_delta: score_delta,
      pattern_tag: Keyword.get(opts, :pattern_tag),
      justification: Keyword.get(opts, :justification, "test"),
      applied_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end

  # ----- extract_pattern_tag/1 -----

  describe "extract_pattern_tag/1" do
    test "returns nil for nil or unclassified input" do
      assert Patterns.extract_pattern_tag(nil) == nil
      assert Patterns.extract_pattern_tag(%{justification: "things went fine"}) == nil
    end

    test "skill_add kind short-circuits to skill_added" do
      assert Patterns.extract_pattern_tag(%{kind: "skill_add"}) == "skill_added"
    end

    test "tool_policy_change with deny list yields tightened_deny" do
      assert "tightened_deny" =
               Patterns.extract_pattern_tag(%{
                 kind: "tool_policy_change",
                 proposed_change: %{"deny" => ["python_exec"]}
               })
    end

    test "tool_policy_change with allow list (no deny) yields tightened_allow" do
      assert "tightened_allow" =
               Patterns.extract_pattern_tag(%{
                 kind: "tool_policy_change",
                 proposed_change: %{"allow" => ["web_search"]}
               })
    end

    test "added_retrieval keyword in justification" do
      assert "added_retrieval" =
               Patterns.extract_pattern_tag(%{
                 kind: "card_edit",
                 justification: "Adds a retrieval step before any tool call."
               })
    end

    test "added_reflexion keyword" do
      assert "added_reflexion" =
               Patterns.extract_pattern_tag(%{
                 kind: "card_edit",
                 justification: "Enable reflexion every 2 turns."
               })
    end

    test "output_format_change keyword" do
      assert "output_format_change" =
               Patterns.extract_pattern_tag(%{
                 kind: "card_edit",
                 justification: "Require cite_sources in output_contract."
               })
    end

    test "prompt_clarify_goal keyword" do
      assert "prompt_clarify_goal" =
               Patterns.extract_pattern_tag(%{
                 kind: "card_edit",
                 justification: "Tighten the goal field to specify the success metric."
               })
    end

    test "uses root_cause_summary when justification is silent" do
      assert "added_retrieval" =
               Patterns.extract_pattern_tag(%{
                 kind: "card_edit",
                 justification: "",
                 root_cause_summary: "Plan skipped retrieval before search call."
               })
    end
  end

  # ----- recent_successful/2 -----

  describe "recent_successful/2" do
    test "returns only applied proposals with positive score_delta" do
      _ = applied!("card-a", 0.10)
      _ = applied!("card-b", 0.05)
      # Negative delta — excluded.
      _ = applied!("card-c", -0.20)
      # Pending — excluded (status != applied).
      _ =
        Repo.insert!(%Proposal{
          kind: "card_edit",
          target: "card-d",
          status: "pending",
          score_delta: 0.30
        })

      ids = Patterns.recent_successful() |> Enum.map(& &1.target)
      assert "card-a" in ids
      assert "card-b" in ids
      refute "card-c" in ids
      refute "card-d" in ids
    end

    test "sorts by score_delta desc" do
      _ = applied!("a", 0.02)
      _ = applied!("b", 0.10)
      _ = applied!("c", 0.06)

      [first, second, third] = Patterns.recent_successful()
      assert first.target == "b"
      assert second.target == "c"
      assert third.target == "a"
    end

    test "excludes the given slug" do
      _ = applied!("keep", 0.10)
      _ = applied!("skip", 0.20)

      targets = Patterns.recent_successful("skip") |> Enum.map(& &1.target)
      assert "keep" in targets
      refute "skip" in targets
    end

    test "respects the limit option" do
      for i <- 1..10, do: applied!("card-#{i}", 0.05 + i * 0.001)
      assert length(Patterns.recent_successful(nil, limit: 3)) == 3
    end

    test "respects the days window" do
      _ = applied!("recent", 0.10)

      # Old proposal — applied_at older than the window.
      old =
        Repo.insert!(%Proposal{
          kind: "card_edit",
          target: "old",
          status: "applied",
          score_delta: 0.20,
          applied_at:
            DateTime.utc_now()
            |> DateTime.truncate(:second)
            |> DateTime.add(-120 * 86_400, :second)
        })

      refute old.id in (Patterns.recent_successful(nil, days: 30) |> Enum.map(& &1.id))
    end
  end

  # ----- validate_inspired_by/1 -----

  describe "validate_inspired_by/1" do
    test "returns the id when it points at a successful applied proposal" do
      p = applied!("source", 0.08)
      assert Patterns.validate_inspired_by(p.id) == p.id
    end

    test "returns nil for a pending / failed / negative-delta proposal" do
      pending =
        Repo.insert!(%Proposal{
          kind: "card_edit",
          target: "x",
          status: "pending"
        })

      negative = applied!("y", -0.05)

      assert Patterns.validate_inspired_by(pending.id) == nil
      assert Patterns.validate_inspired_by(negative.id) == nil
    end

    test "returns nil for missing / nil / empty input" do
      assert Patterns.validate_inspired_by(nil) == nil
      assert Patterns.validate_inspired_by("") == nil
      assert Patterns.validate_inspired_by(Ecto.UUID.generate()) == nil
    end
  end
end
