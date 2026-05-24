defmodule AgenticAiAgent.ImproverSchedulerTest do
  # async: false — touches global env vars + the Improver.Scheduler singleton.
  use AgenticAiAgent.DataCase, async: false

  alias AgenticAiAgent.{Design, Improver, Repo}
  alias AgenticAiAgent.Improver.Proposal

  @card_slug "sch-test-#{System.unique_integer([:positive])}"

  setup do
    # Seed a card so generate_proposal has something to read.
    yaml = """
    slug: #{@card_slug}
    name: Scheduler Test Card
    role: original
    goal: original goal
    scope: original scope
    capabilities: {}
    tool_policy: {}
    reasoning_policy: {}
    safety_policy: {}
    output_contract: {}
    evaluation_mapping: {}
    """

    {:ok, _} = Design.save_card_source(@card_slug, yaml, reason: "seed")

    on_exit(fn ->
      case Design.card_source_path(@card_slug) do
        nil -> :ok
        path -> _ = File.rm(path)
      end

      # Restore env var to a clean state
      System.delete_env("AGENT_SELF_IMPROVE")
    end)

    :ok
  end

  # ----- count_today / count_applied_today -----

  describe "budget counters" do
    test "count_today reflects proposals created in the last 24h" do
      assert Improver.count_today() == 0

      _ =
        Repo.insert!(%Proposal{
          kind: "card_edit",
          target: @card_slug,
          status: "pending"
        })

      assert Improver.count_today() == 1
    end

    test "count_applied_today only counts rows with an applied_at within 24h" do
      assert Improver.count_applied_today() == 0

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Repo.insert!(%Proposal{
        kind: "card_edit",
        target: @card_slug,
        status: "applied",
        applied_at: now
      })

      Repo.insert!(%Proposal{
        kind: "card_edit",
        target: @card_slug,
        status: "applied",
        applied_at: DateTime.add(now, -3 * 86_400, :second)
      })

      assert Improver.count_applied_today() == 1
    end
  end

  # ----- find_previous_card_version -----

  describe "find_previous_card_version/1" do
    test "returns the most recent version before applied_at" do
      # The seed save above created v1. Make a second save to get v2.
      yaml_v2 = """
      slug: #{@card_slug}
      name: Scheduler Test Card v2
      role: original
      goal: original goal
      scope: original scope
      capabilities: {}
      tool_policy: {}
      reasoning_policy: {}
      safety_policy: {}
      output_contract: {}
      evaluation_mapping: {}
      """

      {:ok, _} = Design.save_card_source(@card_slug, yaml_v2, reason: "v2")

      # applied_at well into the future of both versions → previous must
      # return the newest existing version (v2). Avoids timestamp granularity
      # races (utc_datetime is per-second).
      [v2, _v1] = Design.list_card_versions(@card_slug)
      applied_at = DateTime.add(v2.inserted_at, 60, :second)

      p = %Proposal{
        id: Ecto.UUID.generate(),
        kind: "card_edit",
        target: @card_slug,
        applied_at: applied_at
      }

      previous = Improver.find_previous_card_version(p)
      assert previous != nil
      assert previous.id == v2.id
    end

    test "returns nil when the proposal isn't a card_edit or has no applied_at" do
      assert nil ==
               Improver.find_previous_card_version(%Proposal{
                 kind: "card_edit",
                 target: @card_slug,
                 applied_at: nil
               })

      assert nil ==
               Improver.find_previous_card_version(%Proposal{
                 kind: "skill_add",
                 target: @card_slug,
                 applied_at: DateTime.utc_now() |> DateTime.truncate(:second)
               })
    end
  end

  # ----- mark_rolled_back! / mark_auto_promoted! -----

  describe "mark_rolled_back! / mark_auto_promoted!" do
    test "records rollback timestamp + reason" do
      p =
        Repo.insert!(%Proposal{kind: "card_edit", target: @card_slug, status: "applied"})

      updated = Improver.mark_rolled_back!(p, "post-promote drop")
      assert updated.rolled_back_at
      assert updated.rolled_back_reason == "post-promote drop"
    end

    test "sets auto_promoted=true" do
      p =
        Repo.insert!(%Proposal{kind: "card_edit", target: @card_slug, status: "applied"})

      updated = Improver.mark_auto_promoted!(p)
      assert updated.auto_promoted
    end
  end

  # ----- Scheduler tick — kill switch -----

  describe "Scheduler.tick_now/0" do
    test "is no-op when env kill switch is off" do
      # Force-restart the supervised Scheduler so it picks up our env state?
      # Not strictly needed — tick_now reads env on each call via allowed?/0.
      System.put_env("AGENT_SELF_IMPROVE", "off")

      assert %{action: :skipped, reason: :kill_switch} =
               AgenticAiAgent.Improver.Scheduler.tick_now()
    end

    test "is no-op when config is disabled (default)" do
      System.delete_env("AGENT_SELF_IMPROVE")

      assert %{action: :skipped, reason: :disabled} =
               AgenticAiAgent.Improver.Scheduler.tick_now()
    end
  end
end
