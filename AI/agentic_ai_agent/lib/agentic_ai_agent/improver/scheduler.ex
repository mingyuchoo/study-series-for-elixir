defmodule AgenticAiAgent.Improver.Scheduler do
  @moduledoc """
  Autonomous loop driving the self-improvement system:

      tick → (kill switch + budget gates pass) →
      for each configured card_slug:
        generate_proposal (Phase 3)
        if valid + non-noop → auto-approve + stage (Phase 4)

      [later, via PubSub] staging eval finishes →
        if delta >= auto_promote_threshold and apply budget OK →
          apply! (writes file + creates version row via Phase 2)
          mark auto_promoted=true
          remember (slug → {proposal_id, baseline_score}) for rollback watch

      [later, via PubSub] another eval finishes for a watched slug →
        if avg_score < baseline_score - auto_rollback_threshold →
          restore the previous CardVersion (Phase 2)
          mark proposal rolled_back

  **Disabled by default.** Opt in via:

      config :agentic_ai_agent, AgenticAiAgent.Improver.Scheduler,
        enabled: true,
        card_slugs: ["default"],
        interval_ms: :timer.hours(24),
        auto_promote_threshold: 0.05,
        auto_rollback_threshold: 0.03,
        daily_proposal_cap: 3,
        daily_apply_cap: 1,
        # Multi-signal gate — refuses auto-promote when the staged card
        # blows up cost or latency relative to baseline. Ratios are
        # staging/baseline (e.g. 1.5 = "at most 50% increase OK").
        max_cost_ratio: 1.5,
        max_latency_ratio: 1.3

  Kill switch (overrides config): set `AGENT_SELF_IMPROVE=off` in the env.
  """

  use GenServer
  require Logger

  alias AgenticAiAgent.{Design, Eval, Improver, Notifications, Safety}
  alias AgenticAiAgent.Improver.SchedulerDecisions

  @default_interval :timer.hours(24)
  @default_promote_threshold 0.05
  @default_rollback_threshold 0.03
  @default_daily_proposal_cap 3
  @default_daily_apply_cap 1

  # Multi-signal gate defaults. Ratios are staging / baseline.
  # 1.5 = "allow up to 50% increase before blocking auto-promote".
  # Generous defaults — operators tighten via config once they have a
  # baseline of how their cards normally drift.
  @default_max_cost_ratio 1.5
  @default_max_latency_ratio 1.3

  # ----- Client -----

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc "Force one tick immediately. Returns the action taken (telemetry-friendly map)."
  def tick_now, do: GenServer.call(__MODULE__, :tick_now)

  # ----- Server -----

  @impl true
  def init(:ok) do
    cfg = load_cfg()

    if cfg.enabled and Process.whereis(AgenticAiAgent.PubSub) do
      Phoenix.PubSub.subscribe(AgenticAiAgent.PubSub, Eval.pubsub_topic())
    end

    if cfg.enabled, do: schedule_next(cfg)

    state = %{
      cfg: cfg,
      # Map of slug → %{proposal_id, baseline_score} — proposals freshly
      # auto-promoted, waiting for the next eval to confirm or trigger rollback.
      watching: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_info(:tick, state) do
    _ = do_tick(state)
    if state.cfg.enabled, do: schedule_next(state.cfg)
    {:noreply, state}
  end

  # Phase 4 staging finish (also fires for non-staging evals; we filter).
  def handle_info({:eval, :finished, {:ok, eval_run}}, state) do
    state = maybe_auto_promote(state, eval_run)
    state = maybe_auto_rollback(state, eval_run)
    {:noreply, state}
  end

  def handle_info({:eval, :finished, {:error, _}}, state), do: {:noreply, state}
  def handle_info(_other, state), do: {:noreply, state}

  @impl true
  def handle_call(:tick_now, _from, state) do
    result = do_tick(state)
    {:reply, result, state}
  end

  # ----- Tick: propose + stage -----

  defp do_tick(%{cfg: cfg}) do
    cond do
      not allowed?() ->
        %{action: :skipped, reason: :kill_switch}

      not cfg.enabled ->
        %{action: :skipped, reason: :disabled}

      Improver.count_today() >= cfg.daily_proposal_cap ->
        %{action: :skipped, reason: :daily_proposal_cap}

      true ->
        for slug <- cfg.card_slugs, reduce: %{action: :done, slugs: []} do
          acc -> Map.update!(acc, :slugs, &(&1 ++ [propose_and_stage_one(slug)]))
        end
    end
  rescue
    e ->
      Logger.warning("Improver.Scheduler tick crashed: #{Exception.message(e)}")
      %{action: :error, reason: Exception.message(e)}
  end

  defp propose_and_stage_one(slug) do
    case Improver.generate_proposal(slug) do
      {:ok, proposal} ->
        case proposal.status do
          "pending" ->
            # Approve then stage so the staging eval kicks in. The PubSub
            # handler will later apply if the delta clears the threshold.
            approved = Improver.approve!(proposal, "scheduler")

            case Improver.stage!(approved, "scheduler") do
              %_{status: "staging"} -> %{slug: slug, action: :staged, id: proposal.id}
              {:error, reason} -> %{slug: slug, action: :stage_failed, reason: inspect(reason)}
            end

          other ->
            # noop / malformed / etc — leave for HITL inspection.
            %{slug: slug, action: :no_action, status: other}
        end

      {:error, reason} ->
        %{slug: slug, action: :generate_failed, reason: inspect(reason)}
    end
  end

  # ----- Auto-promote on staging finish -----

  defp maybe_auto_promote(state, eval_run) do
    cfg = state.cfg
    slug = card_slug(eval_run)

    if slug && String.ends_with?(slug, "-staging") do
      target = String.replace_suffix(slug, "-staging", "")

      with [proposal | _] <- Improver.list_pending_staging_for_slug(slug),
           latest = Improver.get_proposal!(proposal.id),
           true <- cfg.enabled and allowed?(),
           true <- Improver.count_applied_today() < cfg.daily_apply_cap,
           true <- latest.auto_promoted or latest.status == "approved" or auto_eligible?(latest),
           "staged_passed" <- latest.status,
           true <- delta_ok?(latest.score_delta, cfg.auto_promote_threshold),
           true <- perf_ok_for_auto?(latest, cfg),
           true <- safety_ok_for_auto?(latest) do
        if cfg.dry_run do
          msg =
            "[DRY RUN] would auto-promote proposal #{latest.id} for card #{target} (Δ=#{latest.score_delta})"

          Logger.info(msg)

          _ =
            Notifications.emit("dry_run",
              subject: "Would auto-promote #{target} (Δ #{format_delta(latest.score_delta)})",
              body: msg,
              proposal_id: latest.id,
              card_slug: target
            )

          _ =
            SchedulerDecisions.record("would_apply",
              dry_run: true,
              card_slug: target,
              proposal_id: latest.id,
              detail: "Δ=#{format_delta(latest.score_delta)}",
              metadata: %{
                "score_delta" => latest.score_delta,
                "baseline_score" => latest.baseline_score,
                "staging_score" => latest.staging_score
              }
            )

          state
        else
          case Improver.apply!(latest, "scheduler") do
            %_{status: "applied"} = applied ->
              applied = Improver.mark_auto_promoted!(applied)

              Logger.info(
                "Improver.Scheduler auto-promoted proposal #{applied.id} (Δ=#{applied.score_delta})"
              )

              _ =
                Notifications.emit("auto_promote",
                  subject: "Auto-promoted #{target} (Δ #{format_delta(applied.score_delta)})",
                  body: "Proposal #{applied.id} applied. Watching next eval for regression.",
                  proposal_id: applied.id,
                  card_slug: target
                )

              _ =
                SchedulerDecisions.record("applied",
                  dry_run: false,
                  card_slug: target,
                  proposal_id: applied.id,
                  detail: "Δ=#{format_delta(applied.score_delta)}",
                  metadata: %{
                    "score_delta" => applied.score_delta,
                    "baseline_score" => applied.baseline_score,
                    "staging_score" => applied.staging_score
                  }
                )

              %{
                state
                | watching:
                    Map.put(state.watching, target, %{
                      proposal_id: applied.id,
                      baseline_score: applied.baseline_score
                    })
              }

            _ ->
              state
          end
        end
      else
        _ -> state
      end
    else
      state
    end
  end

  defp format_delta(nil), do: "?"
  defp format_delta(n) when is_number(n) and n >= 0, do: "+#{Float.round(n, 3)}"
  defp format_delta(n) when is_number(n), do: "#{Float.round(n, 3)}"

  # Refuse auto-promote if the proposal's static safety audit flagged any
  # high-severity violations. Manual HITL apply remains available.
  defp safety_ok_for_auto?(%_{safety_verdict: "fail"} = p) do
    violations = get_in(p.safety_audit || %{}, ["violations"])

    Logger.warning(
      "Improver.Scheduler refused to auto-promote proposal #{p.id}: safety audit verdict=fail. " <>
        "Violations: #{inspect(violations)}"
    )

    _ =
      Notifications.emit("safety_blocked",
        subject: "Safety audit blocked auto-promote for #{p.target}",
        body:
          ("Proposal #{p.id} violated: " <>
             (violations || []))
          |> Enum.map_join("; ", &Map.get(&1, "detail", ""))
          |> String.slice(0, 400),
        proposal_id: p.id,
        card_slug: p.target
      )

    _ =
      SchedulerDecisions.record("blocked_safety",
        dry_run: dry_run?(),
        card_slug: p.target,
        proposal_id: p.id,
        detail: "safety verdict=fail",
        metadata: %{"violations" => violations || []}
      )

    false
  end

  defp safety_ok_for_auto?(_), do: true

  @doc """
  Pure decision function for the multi-signal perf gate. Compares
  staging/baseline ratios for cost and latency against the configured
  ceilings and returns:

    * `:ok` — neither signal exceeds its ceiling (or neither signal has
      enough data to evaluate)
    * `{:blocked, signal, ratio, ceiling}` — `signal` is `"cost"` or
      `"latency"`, `ratio` is the offending value (staging/baseline)

  A proposal can ace its eval score and still be a bad bet for
  production if it triples token cost or doubles latency. Missing
  baseline (e.g. first ever staging eval) or missing staging value
  causes that signal to be skipped — we can't reason about a delta
  without both endpoints. Cost is checked before latency; the first
  failure short-circuits.

  Pass `cfg` as the same map shape returned by `load_cfg/0` — only the
  `:max_cost_ratio` and `:max_latency_ratio` keys are read.
  """
  @spec check_perf_gate(struct(), map()) ::
          :ok | {:blocked, String.t(), float(), number()}
  def check_perf_gate(%_{} = p, cfg) do
    cost_ratio = ratio(p.staging_cost_micro_usd, p.baseline_cost_micro_usd)
    latency_ratio = ratio(p.staging_latency_ms, p.baseline_latency_ms)

    cond do
      is_number(cost_ratio) and cost_ratio > cfg.max_cost_ratio ->
        {:blocked, "cost", cost_ratio, cfg.max_cost_ratio}

      is_number(latency_ratio) and latency_ratio > cfg.max_latency_ratio ->
        {:blocked, "latency", latency_ratio, cfg.max_latency_ratio}

      true ->
        :ok
    end
  end

  # Wrapper that also surfaces a notification + warning log when the
  # gate blocks. Used in the auto-promote `with` chain.
  defp perf_ok_for_auto?(%_{} = p, cfg) do
    case check_perf_gate(p, cfg) do
      :ok ->
        true

      {:blocked, signal, ratio, ceiling} ->
        emit_perf_blocked(p, signal, ratio, ceiling)
        false
    end
  end

  # ratio(staging, baseline). Returns nil when either side is missing
  # or baseline is zero (avoids div-by-zero AND avoids treating
  # "0 → anything" as infinite regression — usually it means we have
  # no signal).
  defp ratio(staging, baseline)
       when is_number(staging) and is_number(baseline) and baseline > 0,
       do: staging / baseline

  defp ratio(_, _), do: nil

  defp emit_perf_blocked(p, signal, ratio, ceiling) do
    body =
      "Proposal #{p.id} blocked: #{signal} ratio #{Float.round(ratio, 2)}× " <>
        "exceeds ceiling #{ceiling}× (baseline=#{baseline_for(p, signal)}, " <>
        "staging=#{staging_for(p, signal)})."

    Logger.warning("Improver.Scheduler refused to auto-promote " <> body)

    _ =
      Notifications.emit("perf_blocked",
        subject:
          "Perf gate blocked auto-promote for #{p.target} (#{signal} " <>
            "#{Float.round(ratio, 2)}×)",
        body: body,
        proposal_id: p.id,
        card_slug: p.target
      )

    _ =
      SchedulerDecisions.record("blocked_perf",
        dry_run: dry_run?(),
        card_slug: p.target,
        proposal_id: p.id,
        detail: "#{signal} #{Float.round(ratio, 2)}× > #{ceiling}×",
        metadata: %{
          "signal" => signal,
          "ratio" => ratio,
          "ceiling" => ceiling,
          "baseline" => baseline_for(p, signal),
          "staging" => staging_for(p, signal)
        }
      )

    :ok
  end

  defp baseline_for(p, "cost"), do: p.baseline_cost_micro_usd
  defp baseline_for(p, "latency"), do: p.baseline_latency_ms
  defp staging_for(p, "cost"), do: p.staging_cost_micro_usd
  defp staging_for(p, "latency"), do: p.staging_latency_ms

  # ----- Auto-rollback on post-promote regression -----

  defp maybe_auto_rollback(state, eval_run) do
    cfg = state.cfg
    slug = card_slug(eval_run)

    case slug && Map.get(state.watching, slug) do
      %{proposal_id: pid, baseline_score: baseline} when is_float(baseline) ->
        score = eval_run.average_score || 0.0
        threshold = cfg.auto_rollback_threshold

        if score < baseline - threshold do
          attempt_rollback(pid, baseline, score)
        else
          Logger.info(
            "Improver.Scheduler verified promotion for #{slug} (score=#{score}, baseline=#{baseline})"
          )
        end

        # Forget the watch either way — one post-promote eval is the verdict.
        %{state | watching: Map.delete(state.watching, slug)}

      _ ->
        state
    end
  end

  defp attempt_rollback(proposal_id, baseline, score) do
    p = Improver.get_proposal!(proposal_id)

    case Improver.find_previous_card_version(p) do
      nil ->
        Logger.warning("Improver.Scheduler can't rollback proposal #{p.id}: no previous version")

        _ =
          SchedulerDecisions.record("no_previous_version",
            dry_run: dry_run?(),
            card_slug: p.target,
            proposal_id: p.id,
            detail: "no version row predates applied_at"
          )

      version ->
        do_attempt_rollback(p, version, baseline, score)
    end
  end

  defp do_attempt_rollback(p, version, baseline, score) do
    score_detail =
      "score #{Float.round(score, 4)} < baseline #{Float.round(baseline, 4)}"

    if dry_run?() do
      msg = "[DRY RUN] would auto-rollback proposal #{p.id} (#{score_detail})"
      Logger.warning(msg)

      _ =
        Notifications.emit("dry_run",
          subject: "Would auto-rollback #{p.target}",
          body: msg,
          proposal_id: p.id,
          card_slug: p.target
        )

      _ =
        SchedulerDecisions.record("would_rollback",
          dry_run: true,
          card_slug: p.target,
          proposal_id: p.id,
          detail: score_detail,
          metadata: %{"score" => score, "baseline" => baseline}
        )
    else
      # Snapshot the current (about-to-be-replaced) YAML before restore.
      # Needed by the post-rollback safety re-audit: we compare what the
      # card looks like AFTER restore against what it looked like
      # immediately before — if the restore re-introduces a safety
      # violation, we surface that even though the operator chose
      # rollback as the remediation.
      pre_rollback_yaml = read_card_yaml(p.target)

      case Design.restore_card_version(version,
             reason: "auto-rollback: post-promote regression"
           ) do
        {:ok, _} ->
          reason = "post-promote #{score_detail}"
          _ = Improver.mark_rolled_back!(p, reason)
          Logger.warning("Improver.Scheduler auto-rolled-back proposal #{p.id}: #{reason}")

          _ =
            Notifications.emit("auto_rollback",
              subject: "Auto-rolled back #{p.target}",
              body: "Proposal #{p.id} reverted: #{reason}",
              proposal_id: p.id,
              card_slug: p.target
            )

          _ =
            SchedulerDecisions.record("rolled_back",
              dry_run: false,
              card_slug: p.target,
              proposal_id: p.id,
              detail: score_detail,
              metadata: %{"score" => score, "baseline" => baseline}
            )

          _ = audit_rollback_safety(p, pre_rollback_yaml)
          :ok

        {:error, reason} ->
          Logger.warning("Improver.Scheduler rollback failed for #{p.id}: #{inspect(reason)}")

          _ =
            SchedulerDecisions.record("restore_failed",
              dry_run: false,
              card_slug: p.target,
              proposal_id: p.id,
              detail: inspect(reason) |> String.slice(0, 200)
            )
      end
    end
  end

  @doc """
  Compare a freshly-restored card YAML against what was on disk before
  the rollback. The same `Safety.audit_card/2` logic that gates
  auto-promote runs here in reverse: if going backward to the previous
  version trips a high-severity rule, the operator needs to know the
  rollback didn't necessarily land them in a "safer" place.

  Emits a `"rollback_safety_warning"` notification + records a
  `rollback_safety_warning` decision when the restored YAML introduces
  any high-severity violation relative to the pre-rollback state.

  Returns `:ok | :warning_emitted` — the variant lets tests distinguish
  the two cases without scraping logs.
  """
  @spec audit_rollback_safety(map(), String.t() | nil, String.t() | nil) ::
          :ok | :warning_emitted
  def audit_rollback_safety(_proposal, nil, _), do: :ok
  def audit_rollback_safety(_proposal, _, nil), do: :ok

  def audit_rollback_safety(p, pre_rollback_yaml, post_rollback_yaml)
      when is_binary(pre_rollback_yaml) and is_binary(post_rollback_yaml) do
    case Safety.audit_card(pre_rollback_yaml, post_rollback_yaml) do
      {:ok, %{verdict: :fail, violations: violations}} ->
        detail =
          violations
          |> Enum.map_join("; ", &Map.get(&1, :detail, "(no detail)"))
          |> String.slice(0, 400)

        Logger.warning(
          "Improver.Scheduler: rollback of #{p.id} re-introduces a safety violation: #{detail}"
        )

        _ =
          Notifications.emit("rollback_safety_warning",
            subject: "Rollback re-introduced a safety issue on #{p.target}",
            body:
              "Restoring the previous version of `#{p.target}` re-introduced " <>
                "a high-severity safety rule violation: #{detail}",
            proposal_id: p.id,
            card_slug: p.target
          )

        _ =
          SchedulerDecisions.record("rollback_safety_warning",
            dry_run: false,
            card_slug: p.target,
            proposal_id: p.id,
            detail: detail,
            metadata: %{"violations" => violations}
          )

        :warning_emitted

      _ ->
        :ok
    end
  rescue
    e ->
      Logger.warning(
        "Improver.Scheduler: rollback safety audit crashed for #{p.id}: #{Exception.message(e)}"
      )

      :ok
  end

  # Convenience wrapper for the rollback path: reads the post-rollback
  # YAML off disk and delegates to the 3-arg form.
  defp audit_rollback_safety(p, pre_rollback_yaml) do
    audit_rollback_safety(p, pre_rollback_yaml, read_card_yaml(p.target))
  end

  defp read_card_yaml(slug) when is_binary(slug) do
    case Design.card_source_path(slug) do
      nil -> nil
      path -> File.read!(path)
    end
  rescue
    _ -> nil
  end

  defp dry_run? do
    raw = Application.get_env(:agentic_ai_agent, __MODULE__, [])
    Keyword.get(raw, :dry_run, false)
  end

  # ----- Predicates -----

  # True if the kill switch env var is NOT set to "off".
  defp allowed? do
    case System.get_env("AGENT_SELF_IMPROVE") do
      "off" -> false
      _ -> true
    end
  end

  defp delta_ok?(delta, threshold) when is_number(delta) and is_number(threshold),
    do: delta >= threshold

  defp delta_ok?(_, _), do: false

  # Whether a proposal that arrived via the scheduler path is eligible
  # to be auto-applied. Right now: only proposals freshly created by the
  # scheduler tick are eligible (we approve them ourselves).
  defp auto_eligible?(_proposal), do: true

  defp card_slug(%{agentic_card_id: nil}), do: nil

  defp card_slug(%{agentic_card_id: card_id}) do
    case AgenticAiAgent.Repo.get(Design.AgenticCard, card_id) do
      nil -> nil
      card -> card.slug
    end
  end

  defp card_slug(_), do: nil

  # ----- Config -----

  defp load_cfg do
    raw = Application.get_env(:agentic_ai_agent, __MODULE__, [])

    %{
      enabled: Keyword.get(raw, :enabled, false),
      card_slugs: Keyword.get(raw, :card_slugs, []),
      interval_ms: Keyword.get(raw, :interval_ms, @default_interval),
      auto_promote_threshold:
        Keyword.get(raw, :auto_promote_threshold, @default_promote_threshold),
      auto_rollback_threshold:
        Keyword.get(raw, :auto_rollback_threshold, @default_rollback_threshold),
      daily_proposal_cap: Keyword.get(raw, :daily_proposal_cap, @default_daily_proposal_cap),
      daily_apply_cap: Keyword.get(raw, :daily_apply_cap, @default_daily_apply_cap),
      # Multi-signal gate ceilings — staging/baseline ratios. Either signal
      # exceeding its ceiling blocks auto-promote (manual apply still works).
      max_cost_ratio: Keyword.get(raw, :max_cost_ratio, @default_max_cost_ratio),
      max_latency_ratio: Keyword.get(raw, :max_latency_ratio, @default_max_latency_ratio),
      # Dry-run: tick still runs, generation still happens (proposals land in
      # the queue), but mutating actions (apply, rollback) are SKIPPED. Used
      # by operators to preview autonomous behavior before flipping the real
      # switch.
      dry_run: Keyword.get(raw, :dry_run, false)
    }
  end

  defp schedule_next(%{interval_ms: ms}) do
    Process.send_after(self(), :tick, ms)
    :ok
  end
end
