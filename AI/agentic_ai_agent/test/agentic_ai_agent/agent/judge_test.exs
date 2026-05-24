defmodule AgenticAiAgent.Agent.JudgeTest do
  use AgenticAiAgent.DataCase, async: false

  alias AgenticAiAgent.Agent.Judge
  alias AgenticAiAgent.Feedback
  alias AgenticAiAgent.Feedback.GoldenCandidate
  alias AgenticAiAgent.Traces.Run

  defp insert_run!(opts \\ []) do
    %Run{
      user_input: Keyword.get(opts, :user_input, "what is the capital of France?"),
      final_answer: Keyword.get(opts, :final_answer, "Berlin."),
      status: "done",
      started_at: DateTime.utc_now()
    }
    |> Repo.insert!()
  end

  # ----- critique/3 — early returns / structural -----

  describe "critique/3 — early returns" do
    test "empty input or answer → :empty_input_or_answer" do
      assert {:error, :empty_input_or_answer} = Judge.critique("", "ans")
      assert {:error, :empty_input_or_answer} = Judge.critique("q", "")
      assert {:error, :empty_input_or_answer} = Judge.critique(nil, "ans")
    end
  end

  # ----- judge_run/2 — config gating -----

  describe "judge_run/2 — config" do
    test "disabled card → {:skipped, :disabled}" do
      run = insert_run!()
      card = %{slug: "default", reasoning_policy: %{}}

      assert {:skipped, :disabled} = Judge.judge_run(run, card)
    end

    test "short user_input → {:skipped, :input_too_short}" do
      run = insert_run!(user_input: "hi")
      card = %{slug: "default", reasoning_policy: %{"auto_judge" => %{"enabled" => true}}}

      assert {:skipped, :input_too_short} = Judge.judge_run(run, card)
    end

    test "empty final_answer → {:skipped, :empty_answer}" do
      run = insert_run!(final_answer: "")
      card = %{slug: "default", reasoning_policy: %{"auto_judge" => %{"enabled" => true}}}

      assert {:skipped, :empty_answer} = Judge.judge_run(run, card)
    end

    test "enabled + valid run with no LLM configured → {:error, _} (graceful)" do
      run = insert_run!()
      card = %{slug: "default", reasoning_policy: %{"auto_judge" => %{"enabled" => true}}}

      assert {:error, _reason} = Judge.judge_run(run, card)
    end
  end

  # ----- Feedback.flag_from_judge/3 — direct unit tests -----

  describe "Feedback.flag_from_judge/3" do
    test "creates a candidate with flagged_by=judge + score" do
      run = insert_run!()
      card = %{slug: "default"}
      judgment = %{score: 0.20, verdict: "bad", reason: "Wrong country"}

      assert {:ok, %GoldenCandidate{} = c} = Feedback.flag_from_judge(run, card, judgment)
      assert c.flagged_by == "judge"
      assert c.judge_score == 0.20
      assert c.user_note =~ "Wrong country"
      assert c.target_card_slug == "default"
      assert c.status == "pending"
    end

    test "dedups per run + flagged_by=judge — second call returns :already_flagged" do
      run = insert_run!()
      card = %{slug: "default"}
      j1 = %{score: 0.1, verdict: "bad", reason: "first reason"}
      j2 = %{score: 0.05, verdict: "bad", reason: "second reason"}

      {:ok, first} = Feedback.flag_from_judge(run, card, j1)

      assert {:already_flagged, %GoldenCandidate{id: same_id}} =
               Feedback.flag_from_judge(run, card, j2)

      assert same_id == first.id

      # Confirm only one row exists for this run.
      rows =
        from(c in GoldenCandidate, where: c.run_id == ^run.id and c.flagged_by == "judge")
        |> Repo.all()

      assert length(rows) == 1
    end

    test "human flag (Feedback.flag/2) and judge flag coexist as separate rows" do
      run = insert_run!()
      _ = Feedback.flag(run.id, flagged_by: "chat-user")
      _ = Feedback.flag_from_judge(run, nil, %{score: 0.2, verdict: "bad", reason: "test"})

      rows = from(c in GoldenCandidate, where: c.run_id == ^run.id) |> Repo.all()
      assert length(rows) == 2
    end
  end

  # ----- praise_from_judge symmetry -----

  describe "Feedback.praise_from_judge/3" do
    test "creates a positive candidate with polarity=positive" do
      run = insert_run!()
      card = %{slug: "default"}
      judgment = %{score: 0.92, verdict: "good", reason: "Direct and grounded"}

      assert {:ok, %GoldenCandidate{} = c} = Feedback.praise_from_judge(run, card, judgment)
      assert c.polarity == "positive"
      assert c.flagged_by == "judge"
      assert c.judge_score == 0.92
    end

    test "negative judge flag and positive judge praise on same run coexist" do
      run = insert_run!()
      card = %{slug: "default"}

      _ = Feedback.flag_from_judge(run, card, %{score: 0.1, verdict: "bad", reason: "x"})
      _ = Feedback.praise_from_judge(run, card, %{score: 0.95, verdict: "good", reason: "y"})

      rows = from(c in GoldenCandidate, where: c.run_id == ^run.id) |> Repo.all()
      assert length(rows) == 2

      polarities = rows |> Enum.map(& &1.polarity) |> Enum.sort()
      assert polarities == ["negative", "positive"]
    end
  end
end
