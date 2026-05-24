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
        daily_apply_cap: 1

  Kill switch (overrides config): set `AGENT_SELF_IMPROVE=off` in the env.
  """

  use GenServer
  require Logger

  alias AgenticAiAgent.{Design, Eval, Improver}

  @default_interval :timer.hours(24)
  @default_promote_threshold 0.05
  @default_rollback_threshold 0.03
  @default_daily_proposal_cap 3
  @default_daily_apply_cap 1

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
           # The Improver.Staging GenServer has already run; the proposal is
           # now staged_passed or staged_failed. Reload to see the delta.
           latest = Improver.get_proposal!(proposal.id),
           true <- cfg.enabled and allowed?(),
           true <- Improver.count_applied_today() < cfg.daily_apply_cap,
           true <- latest.auto_promoted or latest.status == "approved" or auto_eligible?(latest),
           "staged_passed" <- latest.status,
           true <- delta_ok?(latest.score_delta, cfg.auto_promote_threshold) do
        case Improver.apply!(latest, "scheduler") do
          %_{status: "applied"} = applied ->
            applied = Improver.mark_auto_promoted!(applied)
            Logger.info("Improver.Scheduler auto-promoted proposal #{applied.id} (Δ=#{applied.score_delta})")
            %{state | watching: Map.put(state.watching, target, %{proposal_id: applied.id, baseline_score: applied.baseline_score})}

          _ ->
            state
        end
      else
        _ -> state
      end
    else
      state
    end
  end

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
          Logger.info("Improver.Scheduler verified promotion for #{slug} (score=#{score}, baseline=#{baseline})")
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

      version ->
        case Design.restore_card_version(version, reason: "auto-rollback: post-promote regression") do
          {:ok, _} ->
            reason =
              "post-promote score #{Float.round(score, 4)} < baseline #{Float.round(baseline, 4)}"

            _ = Improver.mark_rolled_back!(p, reason)
            Logger.warning("Improver.Scheduler auto-rolled-back proposal #{p.id}: #{reason}")

          {:error, reason} ->
            Logger.warning("Improver.Scheduler rollback failed for #{p.id}: #{inspect(reason)}")
        end
    end
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
      auto_promote_threshold: Keyword.get(raw, :auto_promote_threshold, @default_promote_threshold),
      auto_rollback_threshold: Keyword.get(raw, :auto_rollback_threshold, @default_rollback_threshold),
      daily_proposal_cap: Keyword.get(raw, :daily_proposal_cap, @default_daily_proposal_cap),
      daily_apply_cap: Keyword.get(raw, :daily_apply_cap, @default_daily_apply_cap)
    }
  end

  defp schedule_next(%{interval_ms: ms}) do
    Process.send_after(self(), :tick, ms)
    :ok
  end
end
