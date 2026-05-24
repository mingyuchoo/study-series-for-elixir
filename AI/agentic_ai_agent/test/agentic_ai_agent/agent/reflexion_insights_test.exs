defmodule AgenticAiAgent.Agent.ReflexionInsightsTest do
  use AgenticAiAgent.DataCase, async: false

  alias AgenticAiAgent.Agent.ReflexionInsights
  alias AgenticAiAgent.Agent.ReflexionInsights.Insight
  alias AgenticAiAgent.Notifications.Notification
  alias AgenticAiAgent.Traces.Run

  @card_slug "rcrit-card-#{System.unique_integer([:positive])}"

  defp insert_run!(opts \\ []) do
    %Run{
      user_input: Keyword.get(opts, :user_input, "what is X?"),
      status: Keyword.get(opts, :status, "done"),
      started_at: DateTime.utc_now()
    }
    |> Repo.insert!()
  end

  defp card, do: %{slug: @card_slug}

  # ----- extract_theme/1 -----

  describe "extract_theme/1" do
    test "returns nil for empty / nil input" do
      assert ReflexionInsights.extract_theme(nil) == nil
      assert ReflexionInsights.extract_theme("") == nil
    end

    test "classifies missing retrieve step" do
      assert "missing_retrieve" =
               ReflexionInsights.extract_theme(
                 "The planner skipped retrieve before calling web_search."
               )
    end

    test "classifies hallucination keywords" do
      assert "hallucination" =
               ReflexionInsights.extract_theme("The answer fabricated a citation.")
    end

    test "classifies looping" do
      assert "looping" =
               ReflexionInsights.extract_theme(
                 "Agent keeps repeating the same step with no progress."
               )
    end

    test "returns nil for an unclassified critique" do
      assert ReflexionInsights.extract_theme("Everything went fine, no issues.") == nil
    end
  end

  # ----- record/3 -----

  describe "record/3" do
    test "inserts an insight with extracted theme" do
      run = insert_run!()
      note = "Agent skipped retrieve before tool call."

      assert {:ok, %Insight{} = i, :new} = ReflexionInsights.record(run, card(), note)
      assert i.run_id == run.id
      assert i.card_slug == @card_slug
      assert i.theme == "missing_retrieve"
      assert i.critique == note
    end

    test "is idempotent per run (returns :existing on repeat)" do
      run = insert_run!()
      {:ok, first, :new} = ReflexionInsights.record(run, card(), "skipped retrieve")
      {:ok, second, :existing} = ReflexionInsights.record(run, card(), "skipped retrieve")

      assert first.id == second.id
    end

    test "returns :empty_critique on nil / blank" do
      assert {:error, :empty_critique} = ReflexionInsights.record(insert_run!(), card(), nil)
      assert {:error, :empty_critique} = ReflexionInsights.record(insert_run!(), card(), "")
    end

    test "truncates very long critique to fit the column" do
      run = insert_run!()
      big = String.duplicate("x", 10_000)
      {:ok, i, :new} = ReflexionInsights.record(run, card(), big)
      assert String.length(i.critique) == 4_000
    end
  end

  # ----- Saturation notification -----

  describe "saturation notification" do
    test "fires exactly on threshold crossing, not on every subsequent run" do
      # The default saturation_threshold is 3.
      slug = "sat-card-#{System.unique_integer([:positive])}"
      note = "skipped retrieve before search"

      for _ <- 1..2 do
        {:ok, _, :new} = ReflexionInsights.record(insert_run!(), %{slug: slug}, note)
      end

      # Two below threshold — no notification.
      assert Repo.aggregate(
               from(n in Notification, where: n.kind == "reflexion_saturation"),
               :count,
               :id
             ) == 0

      # Third hit crosses the threshold.
      {:ok, _, :new} = ReflexionInsights.record(insert_run!(), %{slug: slug}, note)

      n1 =
        Repo.one(from(n in Notification, where: n.kind == "reflexion_saturation"))

      assert n1
      assert n1.card_slug == slug
      assert n1.subject =~ "missing_retrieve"
      assert n1.subject =~ "#{slug}"

      # Fourth hit must NOT re-fire — operator already alerted.
      {:ok, _, :new} = ReflexionInsights.record(insert_run!(), %{slug: slug}, note)

      assert Repo.aggregate(
               from(n in Notification, where: n.kind == "reflexion_saturation"),
               :count,
               :id
             ) == 1
    end
  end

  # ----- recurring_themes_for_card/2 -----

  describe "recurring_themes_for_card/2" do
    test "returns empty for an unknown slug" do
      assert ReflexionInsights.recurring_themes_for_card("ghost-slug") == []
    end

    test "groups by theme and returns only those meeting threshold" do
      slug = "agg-card-#{System.unique_integer([:positive])}"

      # 3 missing_retrieve, 2 hallucination, 1 looping — with default
      # threshold=3 only missing_retrieve should be returned.
      Enum.each(1..3, fn _ ->
        {:ok, _, :new} =
          ReflexionInsights.record(insert_run!(), %{slug: slug}, "skipped retrieve")
      end)

      Enum.each(1..2, fn _ ->
        {:ok, _, :new} =
          ReflexionInsights.record(insert_run!(), %{slug: slug}, "fabricated a citation")
      end)

      {:ok, _, :new} =
        ReflexionInsights.record(
          insert_run!(),
          %{slug: slug},
          "agent keeps looping with no progress"
        )

      themes = ReflexionInsights.recurring_themes_for_card(slug)
      assert length(themes) == 1
      [t] = themes
      assert t.theme == "missing_retrieve"
      assert t.count == 3
      assert is_binary(t.sample_critique)
    end

    test "honors a custom threshold" do
      slug = "thr-card-#{System.unique_integer([:positive])}"

      Enum.each(1..2, fn _ ->
        ReflexionInsights.record(insert_run!(), %{slug: slug}, "skipped retrieve")
      end)

      # threshold=2 should now surface the theme (default 3 wouldn't).
      themes = ReflexionInsights.recurring_themes_for_card(slug, threshold: 2)
      assert [%{theme: "missing_retrieve", count: 2}] = themes
    end
  end

  # ----- link_proposal!/3 -----

  describe "link_proposal!/3" do
    alias AgenticAiAgent.Improver.Proposal

    test "sets triggered_proposal_id on all matching unlinked insights" do
      slug = "link-card-#{System.unique_integer([:positive])}"

      # Two missing_retrieve, one hallucination on the same card.
      for _ <- 1..2 do
        ReflexionInsights.record(insert_run!(), %{slug: slug}, "skipped retrieve before search")
      end

      ReflexionInsights.record(insert_run!(), %{slug: slug}, "fabricated a citation")

      proposal =
        Repo.insert!(%Proposal{
          kind: "card_edit",
          target: slug,
          status: "pending"
        })

      n = ReflexionInsights.link_proposal!(slug, ["missing_retrieve"], proposal.id)
      assert n == 2

      linked =
        Repo.all(from(i in Insight, where: i.triggered_proposal_id == ^proposal.id))

      assert length(linked) == 2
      assert Enum.all?(linked, &(&1.theme == "missing_retrieve"))
    end

    test "no-op for empty themes / nil args" do
      assert 0 == ReflexionInsights.link_proposal!(nil, ["x"], "id")
      assert 0 == ReflexionInsights.link_proposal!("slug", [], "id")
      assert 0 == ReflexionInsights.link_proposal!("slug", ["x"], nil)
    end
  end
end
