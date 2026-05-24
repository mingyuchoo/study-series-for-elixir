defmodule AgenticAiAgent.Improver.SchedulerDecisionsTest do
  use AgenticAiAgent.DataCase, async: false

  alias AgenticAiAgent.Improver.SchedulerDecisions
  alias AgenticAiAgent.Improver.SchedulerDecisions.Decision

  # ----- record/2 -----

  describe "record/2" do
    test "inserts a row with required fields and a JSON-safe metadata map" do
      assert {:ok, %Decision{} = d} =
               SchedulerDecisions.record("applied",
                 card_slug: "default",
                 detail: "Δ=+0.07",
                 metadata: %{"score_delta" => 0.07, "baseline_score" => 0.80}
               )

      assert d.action == "applied"
      assert d.dry_run == false
      assert d.card_slug == "default"
      assert d.metadata["score_delta"] == 0.07
    end

    test "rejects an unknown action" do
      assert {:error, %Ecto.Changeset{} = cs} = SchedulerDecisions.record("noodle")

      assert "is invalid" in errors_on(cs).action
    end

    test "dry_run defaults to false" do
      {:ok, d} = SchedulerDecisions.record("blocked_safety", card_slug: "x")
      assert d.dry_run == false
    end
  end

  # ----- list/1 -----

  describe "list/1" do
    setup do
      {:ok, _} =
        SchedulerDecisions.record("applied",
          dry_run: false,
          card_slug: "card-a"
        )

      {:ok, _} =
        SchedulerDecisions.record("would_apply",
          dry_run: true,
          card_slug: "card-a"
        )

      {:ok, _} =
        SchedulerDecisions.record("rolled_back",
          dry_run: false,
          card_slug: "card-b"
        )

      :ok
    end

    test "filters by action" do
      assert [%Decision{action: "applied"}] = SchedulerDecisions.list(action: "applied")
    end

    test "filters by card_slug" do
      rows = SchedulerDecisions.list(card_slug: "card-a")
      assert length(rows) == 2
      assert Enum.all?(rows, &(&1.card_slug == "card-a"))
    end

    test "filters by dry_run mode" do
      assert [%Decision{action: "would_apply"}] =
               SchedulerDecisions.list(dry_run: true)
    end

    test "returns every decision when no filters" do
      # All three setup rows land in the same UTC second, so the within-
      # second ordering isn't deterministic. We only assert presence.
      rows = SchedulerDecisions.list()
      actions = rows |> Enum.map(& &1.action) |> Enum.sort()
      assert actions == ~w(applied rolled_back would_apply)
    end
  end

  # ----- summary/1 -----

  describe "summary/1" do
    test "counts decisions grouped by {action, dry_run}" do
      for _ <- 1..3 do
        SchedulerDecisions.record("applied", dry_run: false, card_slug: "x")
      end

      for _ <- 1..2 do
        SchedulerDecisions.record("would_apply", dry_run: true, card_slug: "x")
      end

      SchedulerDecisions.record("blocked_safety", dry_run: false, card_slug: "x")

      sum = SchedulerDecisions.summary(30)

      assert sum[{"applied", false}] == 3
      assert sum[{"would_apply", true}] == 2
      assert sum[{"blocked_safety", false}] == 1
    end

    test "returns empty map when no decisions in window" do
      assert SchedulerDecisions.summary(30) == %{}
    end
  end
end
