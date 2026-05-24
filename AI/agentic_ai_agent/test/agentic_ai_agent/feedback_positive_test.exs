defmodule AgenticAiAgent.FeedbackPositiveTest do
  use AgenticAiAgent.DataCase, async: false

  alias AgenticAiAgent.{Feedback, Repo}
  alias AgenticAiAgent.Feedback.GoldenCandidate
  alias AgenticAiAgent.Traces.Run

  setup do
    # Sandbox the wins.jsonl + regressions.jsonl so we don't pollute
    # priv files. Both paths are tracked + restored.
    paths_to_backup = [Feedback.wins_path(), Feedback.regressions_path()]

    backups =
      Enum.map(paths_to_backup, fn p ->
        {p, if(File.exists?(p), do: File.read!(p), else: nil)}
      end)

    on_exit(fn ->
      Enum.each(backups, fn {p, body} ->
        case body do
          nil -> _ = File.rm(p)
          b -> _ = File.write(p, b)
        end
      end)
    end)

    :ok
  end

  defp insert_run!(opts \\ []) do
    %Run{
      user_input: Keyword.get(opts, :user_input, "what is the capital of France?"),
      final_answer: Keyword.get(opts, :final_answer, "Paris."),
      status: Keyword.get(opts, :status, "done"),
      started_at: DateTime.utc_now()
    }
    |> Repo.insert!()
  end

  # ----- praise/2 -----

  describe "praise/2" do
    test "creates a positive golden candidate" do
      run = insert_run!()

      assert {:ok, %GoldenCandidate{} = c} =
               Feedback.praise(run.id,
                 flagged_by: "chat-user",
                 target_card_slug: "default"
               )

      assert c.polarity == "positive"
      assert c.user_input == "what is the capital of France?"
      assert c.assistant_answer == "Paris."
      assert c.flagged_by == "chat-user"
      assert c.target_card_slug == "default"
      assert c.status == "pending"
    end

    test "negative flag and positive praise on the same run coexist" do
      run = insert_run!()
      {:ok, neg} = Feedback.flag(run.id, flagged_by: "chat-user")
      {:ok, pos} = Feedback.praise(run.id, flagged_by: "chat-user")

      assert neg.polarity == "negative"
      assert pos.polarity == "positive"

      rows = from(c in GoldenCandidate, where: c.run_id == ^run.id) |> Repo.all()
      assert length(rows) == 2
    end

    test "returns :run_not_found for a missing run id" do
      assert {:error, :run_not_found} = Feedback.praise(Ecto.UUID.generate())
    end
  end

  # ----- praise_from_judge/3 -----

  describe "praise_from_judge/3" do
    test "creates a positive candidate carrying the judge score" do
      run = insert_run!()
      card = %{slug: "default"}

      assert {:ok, %GoldenCandidate{} = c} =
               Feedback.praise_from_judge(run, card, %{
                 score: 0.92,
                 verdict: "good",
                 reason: "directly answered with correct city"
               })

      assert c.polarity == "positive"
      assert c.judge_score == 0.92
      assert c.flagged_by == "judge"
      assert c.user_note =~ "directly answered"
    end

    test "is idempotent per (run, polarity=positive) — second call returns :already_flagged" do
      run = insert_run!()
      card = %{slug: "default"}
      j = %{score: 0.9, verdict: "good", reason: "great"}

      {:ok, first} = Feedback.praise_from_judge(run, card, j)

      assert {:already_flagged, %GoldenCandidate{id: same}} =
               Feedback.praise_from_judge(run, card, j)

      assert same == first.id
    end

    test "praise and flag from judge coexist as separate rows on the same run" do
      run = insert_run!()
      card = %{slug: "default"}

      {:ok, _} =
        Feedback.flag_from_judge(run, card, %{score: 0.1, verdict: "bad", reason: "wrong"})

      {:ok, _} =
        Feedback.praise_from_judge(run, card, %{score: 0.95, verdict: "good", reason: "yes"})

      rows = from(c in GoldenCandidate, where: c.run_id == ^run.id) |> Repo.all()
      assert length(rows) == 2
      assert Enum.map(rows, & &1.polarity) |> Enum.sort() == ["negative", "positive"]
    end
  end

  # ----- promote!/2 for positives -----

  describe "promote!/2 (positive)" do
    test "writes to wins.jsonl and marks promoted" do
      run = insert_run!()
      {:ok, c} = Feedback.praise(run.id, target_card_slug: "default")

      assert {:ok, promoted} = Feedback.promote!(c, by: "tester")
      assert promoted.status == "promoted"
      assert promoted.promoted_to_path =~ "wins.jsonl"

      # The wins.jsonl now has one row that matches our candidate.
      contents = File.read!(Feedback.wins_path())
      assert contents =~ "\"task_type\":\"win\""
      assert contents =~ "\"final_answer_contains\":\"Paris.\""
      assert contents =~ "\"polarity\":\"positive\""
    end

    test ":empty_assistant_answer when the run had no final answer" do
      run = insert_run!(final_answer: "")
      {:ok, c} = Feedback.praise(run.id)

      assert {:error, :empty_assistant_answer} = Feedback.promote!(c, by: "tester")
    end

    test ":already_promoted on repeat" do
      run = insert_run!()
      {:ok, c} = Feedback.praise(run.id)
      {:ok, p1} = Feedback.promote!(c, by: "tester")
      assert {:error, :already_promoted} = Feedback.promote!(p1, by: "tester")
    end

    test "negative promote still routes to regressions.jsonl (unchanged)" do
      run = insert_run!()
      {:ok, c} = Feedback.flag(run.id)

      {:ok, p} =
        Feedback.promote!(c, corrected_answer: "Paris is the capital of France.", by: "tester")

      assert p.promoted_to_path =~ "regressions.jsonl"
      assert File.read!(Feedback.regressions_path()) =~ "\"task_type\":\"regression\""
    end
  end

  # ----- recent_positive_for_card/2 -----

  describe "recent_positive_for_card/2" do
    test "returns only positive candidates for the slug" do
      slug = "pos-q-#{System.unique_integer([:positive])}"
      run = insert_run!()

      # Same card, mix of polarities.
      {:ok, _} = Feedback.flag(run.id, target_card_slug: slug)
      {:ok, _} = Feedback.praise(run.id, target_card_slug: slug)

      # Different card — must not appear.
      other_run = insert_run!()
      {:ok, _} = Feedback.praise(other_run.id, target_card_slug: "other-card")

      [only_one] = Feedback.recent_positive_for_card(slug)
      assert only_one.polarity == "positive"
      assert only_one.target_card_slug == slug
    end

    test "honors the statuses option" do
      slug = "pos-q-#{System.unique_integer([:positive])}"
      run = insert_run!()

      {:ok, pending} = Feedback.praise(run.id, target_card_slug: slug)
      {:ok, _promoted} = Feedback.promote!(pending, by: "tester")

      # Default (pending+promoted) sees it.
      assert [_] = Feedback.recent_positive_for_card(slug)

      # Restricting to just pending → nothing.
      assert [] = Feedback.recent_positive_for_card(slug, statuses: ["pending"])
    end
  end

  # ----- Improver.build_context surfaces positive_patterns -----

  describe "Improver.build_context positive_patterns" do
    alias AgenticAiAgent.{Design, Improver}

    @ctx_slug "ctx-pos-#{System.unique_integer([:positive])}"

    setup do
      yaml = """
      slug: #{@ctx_slug}
      name: ctx pos test
      role: t
      goal: t
      scope: t
      capabilities: {}
      tool_policy: {}
      reasoning_policy: {}
      safety_policy: {}
      output_contract: {}
      evaluation_mapping: {}
      """

      {:ok, _} = Design.save_card_source(@ctx_slug, yaml, reason: "seed")

      on_exit(fn ->
        case Design.card_source_path(@ctx_slug) do
          nil -> :ok
          path -> _ = File.rm(path)
        end
      end)

      :ok
    end

    test "ctx.positive_patterns lists praised answers for the slug" do
      run = insert_run!()
      {:ok, _} = Feedback.praise(run.id, target_card_slug: @ctx_slug)

      ctx = Improver.build_context(@ctx_slug, diagnose: false)
      assert [%GoldenCandidate{polarity: "positive"}] = ctx.positive_patterns
    end

    test "ctx.positive_patterns is empty when nothing praised" do
      ctx = Improver.build_context(@ctx_slug, diagnose: false)
      assert ctx.positive_patterns == []
    end
  end
end
