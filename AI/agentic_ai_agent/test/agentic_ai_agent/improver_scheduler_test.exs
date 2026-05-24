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

  # ----- Multi-signal perf gate -----

  describe "Scheduler.check_perf_gate/2" do
    alias AgenticAiAgent.Improver.Scheduler

    defp gate_cfg(opts \\ []) do
      %{
        max_cost_ratio: Keyword.get(opts, :max_cost_ratio, 1.5),
        max_latency_ratio: Keyword.get(opts, :max_latency_ratio, 1.3)
      }
    end

    test ":ok when neither cost nor latency exceed their ceiling" do
      p = %Proposal{
        baseline_cost_micro_usd: 1_000,
        staging_cost_micro_usd: 1_400,
        baseline_latency_ms: 200,
        staging_latency_ms: 220
      }

      assert :ok = Scheduler.check_perf_gate(p, gate_cfg())
    end

    test "blocks on cost when staging/baseline ratio exceeds max_cost_ratio" do
      p = %Proposal{
        baseline_cost_micro_usd: 1_000,
        staging_cost_micro_usd: 3_000,
        baseline_latency_ms: 200,
        staging_latency_ms: 210
      }

      assert {:blocked, "cost", ratio, 1.5} = Scheduler.check_perf_gate(p, gate_cfg())
      assert ratio == 3.0
    end

    test "blocks on latency when staging/baseline ratio exceeds max_latency_ratio" do
      p = %Proposal{
        baseline_cost_micro_usd: 1_000,
        staging_cost_micro_usd: 1_100,
        baseline_latency_ms: 200,
        staging_latency_ms: 600
      }

      assert {:blocked, "latency", ratio, 1.3} = Scheduler.check_perf_gate(p, gate_cfg())
      assert ratio == 3.0
    end

    test "cost gate fires first when both signals would block" do
      p = %Proposal{
        baseline_cost_micro_usd: 1_000,
        staging_cost_micro_usd: 5_000,
        baseline_latency_ms: 200,
        staging_latency_ms: 5_000
      }

      assert {:blocked, "cost", _, _} = Scheduler.check_perf_gate(p, gate_cfg())
    end

    test "skips a signal when its baseline is missing (no signal → no block)" do
      p = %Proposal{
        baseline_cost_micro_usd: nil,
        staging_cost_micro_usd: 50_000,
        baseline_latency_ms: 200,
        staging_latency_ms: 220
      }

      assert :ok = Scheduler.check_perf_gate(p, gate_cfg())
    end

    test "skips a signal when its baseline is zero (avoids div-by-zero)" do
      p = %Proposal{
        baseline_cost_micro_usd: 0,
        staging_cost_micro_usd: 1_000,
        baseline_latency_ms: 200,
        staging_latency_ms: 210
      }

      assert :ok = Scheduler.check_perf_gate(p, gate_cfg())
    end

    test "respects custom ceilings from config" do
      p = %Proposal{
        baseline_cost_micro_usd: 1_000,
        staging_cost_micro_usd: 1_200,
        baseline_latency_ms: 200,
        staging_latency_ms: 210
      }

      # 1.2x cost — passes the default 1.5 ceiling but fails a strict 1.1.
      assert :ok = Scheduler.check_perf_gate(p, gate_cfg())

      assert {:blocked, "cost", _, 1.1} =
               Scheduler.check_perf_gate(p, gate_cfg(max_cost_ratio: 1.1))
    end
  end

  # ----- Post-rollback safety re-audit -----

  describe "Scheduler.audit_rollback_safety/3" do
    alias AgenticAiAgent.Improver.Scheduler
    alias AgenticAiAgent.Improver.SchedulerDecisions
    alias AgenticAiAgent.Notifications.Notification

    # Persisted proposal — the audit records a decision row whose
    # proposal_id is a FK, so a transient struct would violate it.
    defp p! do
      Repo.insert!(%Proposal{
        kind: "card_edit",
        target: "rollback-test",
        status: "applied"
      })
    end

    defp safe_yaml(allow, deny \\ ["python_exec"]) do
      """
      slug: rollback-test
      name: rb
      role: r
      goal: g
      scope: s
      capabilities: {}
      tool_policy:
        allow: #{inspect(allow)}
        deny: #{inspect(deny)}
      reasoning_policy: {}
      safety_policy:
        human_approval_required_for: [high]
      output_contract: {}
      evaluation_mapping: {}
      """
    end

    test ":ok when post_rollback matches pre_rollback semantically" do
      same = safe_yaml(["web_search"])
      assert :ok = Scheduler.audit_rollback_safety(p!(), same, same)
    end

    test ":ok when nil yaml on either side (defensive)" do
      assert :ok = Scheduler.audit_rollback_safety(p!(), nil, safe_yaml(["web_search"]))
      assert :ok = Scheduler.audit_rollback_safety(p!(), safe_yaml(["web_search"]), nil)
    end

    test "emits :warning_emitted + notification when rollback re-introduces a deny shrink" do
      # Pre-rollback (current safer state) has python_exec denied.
      pre = safe_yaml(["web_search"], ["python_exec"])
      # Post-rollback (older version) had an empty deny list —
      # restoring it loses the python_exec deny → fails safety.
      post = safe_yaml(["web_search"], [])

      assert :warning_emitted = Scheduler.audit_rollback_safety(p!(), pre, post)

      assert [%Notification{kind: "rollback_safety_warning"}] =
               Repo.all(from(n in Notification, where: n.kind == "rollback_safety_warning"))

      assert [%{action: "rollback_safety_warning"}] =
               SchedulerDecisions.list(action: "rollback_safety_warning")
    end

    test "emits :warning_emitted when rollback re-adds a known-risky tool" do
      # Pre-rollback had python_exec removed; post-rollback puts it back.
      pre = safe_yaml(["web_search", "calculator"])
      post = safe_yaml(["web_search", "calculator", "python_exec"])

      assert :warning_emitted = Scheduler.audit_rollback_safety(p!(), pre, post)
    end
  end
end
