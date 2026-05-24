defmodule AgenticAiAgent.Analytics do
  @moduledoc """
  Cross-run aggregations for the `/insights` dashboard. The first half of
  the self-improvement roadmap (Phase 1 in `docs/`): observability so we
  can *see* what to improve before automating it.

  All functions are read-only and accept a `days` integer (default 30) that
  bounds the analysis window via `runs.inserted_at`.

  Every function is defensive: on any DB error it returns an empty result
  shape rather than raising. The Insights page should never break the app.
  """

  import Ecto.Query

  alias AgenticAiAgent.Repo
  alias AgenticAiAgent.Design.AgenticCard
  alias AgenticAiAgent.Eval.{EvalCase, EvalRun}
  alias AgenticAiAgent.Failures.{FailureMode, FailureOccurrence}
  alias AgenticAiAgent.Traces.{Run, ToolCall}

  @default_days 30

  # ----- 1. Run health -----

  @doc """
  Counts + status breakdown + averages for runs inserted within the window.

  Shape:
      %{
        total: 142,
        by_status: %{"done" => 120, "failed" => 18, "running" => 4},
        success_rate: 0.845,
        avg_latency_ms: 4187.2,
        total_cost_micro_usd: 245_810,
        avg_cost_micro_usd: 1730.4
      }
  """
  def run_health(days \\ @default_days) do
    cutoff = cutoff(days)

    by_status =
      Run
      |> where([r], r.inserted_at >= ^cutoff)
      |> group_by([r], r.status)
      |> select([r], {r.status, count(r.id)})
      |> Repo.all()
      |> Map.new()

    total = by_status |> Map.values() |> Enum.sum()

    {avg_latency, total_cost, avg_cost} =
      Run
      |> where([r], r.inserted_at >= ^cutoff)
      |> select([r], {avg(r.latency_ms), sum(r.cost_micro_usd), avg(r.cost_micro_usd)})
      |> Repo.one() || {nil, 0, nil}

    %{
      total: total,
      by_status: by_status,
      success_rate: success_rate(by_status, total),
      avg_latency_ms: to_float(avg_latency),
      total_cost_micro_usd: total_cost || 0,
      avg_cost_micro_usd: to_float(avg_cost)
    }
  rescue
    _ -> empty_run_health()
  end

  defp success_rate(_, 0), do: 0.0
  defp success_rate(by_status, total), do: Map.get(by_status, "done", 0) / total

  defp empty_run_health,
    do: %{
      total: 0,
      by_status: %{},
      success_rate: 0.0,
      avg_latency_ms: nil,
      total_cost_micro_usd: 0,
      avg_cost_micro_usd: nil
    }

  # ----- 2. Top failure modes -----

  @doc """
  Top N failure modes inside the window, sorted by occurrence count
  (most frequent first). Joins the catalog so we get the human-readable
  slug + severity.

  Shape: `[%{slug, name, severity, count, last_seen_at}, ...]`
  """
  def failures_by_mode(days \\ @default_days, limit \\ 10) do
    cutoff = cutoff(days)

    FailureOccurrence
    |> join(:left, [o], m in FailureMode, on: m.id == o.failure_mode_id)
    |> where([o, _m], o.inserted_at >= ^cutoff)
    |> group_by([o, m], [o.failure_mode_id, m.slug, m.name, m.severity])
    |> select([o, m], %{
      slug: m.slug,
      name: m.name,
      severity: m.severity,
      count: count(o.id),
      last_seen_at: max(o.inserted_at)
    })
    |> order_by(desc: 4)
    |> limit(^limit)
    |> Repo.all()
  rescue
    _ -> []
  end

  # ----- 3. Tool usage / error rate -----

  @doc """
  Per-tool call counts, error counts, error rate, and avg latency over
  the window.

  Shape: `[%{tool, calls, errors, error_rate, avg_latency_ms}, ...]`
  sorted by call count desc.
  """
  def tool_stats(days \\ @default_days) do
    cutoff = cutoff(days)

    ToolCall
    |> where([tc], tc.inserted_at >= ^cutoff)
    |> group_by([tc], tc.tool_name)
    |> select([tc], %{
      tool: tc.tool_name,
      calls: count(tc.id),
      errors: fragment("SUM(CASE WHEN ? IS NOT NULL THEN 1 ELSE 0 END)", tc.error),
      avg_latency_ms: avg(tc.latency_ms)
    })
    |> order_by([tc], desc: count(tc.id))
    |> Repo.all()
    |> Enum.map(fn row ->
      errors = row.errors || 0

      Map.merge(row, %{
        errors: errors,
        error_rate: if(row.calls > 0, do: errors / row.calls, else: 0.0),
        avg_latency_ms: to_float(row.avg_latency_ms)
      })
    end)
  rescue
    _ -> []
  end

  # ----- 4. Daily cost + quality -----

  @doc """
  Day-by-day series of run count, total cost (micro-USD), and average
  latency. Useful as a sparkline data source.

  Returned dates are ISO strings (YYYY-MM-DD), sorted oldest → newest.
  Days with no runs are NOT zero-filled (frontend can do that).
  """
  def daily_cost_quality(days \\ @default_days) do
    cutoff = cutoff(days)

    Run
    |> where([r], r.inserted_at >= ^cutoff)
    |> group_by([r], fragment("date(?)", r.inserted_at))
    |> select([r], %{
      date: fragment("date(?)", r.inserted_at),
      runs: count(r.id),
      cost_micro_usd: sum(r.cost_micro_usd),
      avg_latency_ms: avg(r.latency_ms)
    })
    |> order_by([r], asc: fragment("date(?)", r.inserted_at))
    |> Repo.all()
    |> Enum.map(fn row ->
      Map.merge(row, %{
        cost_micro_usd: row.cost_micro_usd || 0,
        avg_latency_ms: to_float(row.avg_latency_ms)
      })
    end)
  rescue
    _ -> []
  end

  # ----- 5. Eval score per card -----

  @doc """
  Latest eval runs grouped by card. For each card, show the most recent
  `:per_card` eval runs (default 5) with their average_score, threshold,
  and pass status.

  Shape:
      [%{card_slug, card_name, runs: [%{id, average_score, pass_threshold, passed_cases, total_cases, finished_at}]}, ...]
  """
  def score_trend_per_card(opts \\ []) do
    per_card = Keyword.get(opts, :per_card, 5)
    limit = Keyword.get(opts, :limit, 50)

    rows =
      EvalRun
      |> join(:inner, [er], c in AgenticCard, on: c.id == er.agentic_card_id)
      |> where([er], er.status == "done")
      |> order_by([er], desc: er.inserted_at)
      |> limit(^limit)
      |> select([er, c], %{
        card_slug: c.slug,
        card_name: c.name,
        eval_id: er.id,
        average_score: er.average_score,
        pass_threshold: er.pass_threshold,
        passed_cases: er.passed_cases,
        total_cases: er.total_cases,
        finished_at: er.finished_at
      })
      |> Repo.all()

    rows
    |> Enum.group_by(& &1.card_slug)
    |> Enum.map(fn {slug, group} ->
      sorted = Enum.sort_by(group, & &1.finished_at, {:desc, DateTime})

      %{
        card_slug: slug,
        card_name: List.first(sorted).card_name,
        runs: Enum.take(sorted, per_card)
      }
    end)
    |> Enum.sort_by(& &1.card_slug)
  rescue
    _ -> []
  end

  # ----- 5b. Skill (sub-agent) stats -----

  @doc """
  Aggregate stats per skill across sub-agent runs (where `skill_slug` is
  populated). Distinguishes failure of a SKILL invocation from generic
  failures elsewhere in the system.

  Shape:
      [
        %{
          skill_slug,
          total, by_status, success_rate,
          avg_latency_ms, avg_cost_micro_usd,
          failed
        }
      ]
  sorted by `total` desc.
  """
  def skill_stats(days \\ @default_days) do
    cutoff = cutoff(days)

    Run
    |> where([r], r.inserted_at >= ^cutoff and not is_nil(r.skill_slug))
    |> group_by([r], [r.skill_slug, r.status])
    |> select([r], %{
      skill_slug: r.skill_slug,
      status: r.status,
      count: count(r.id),
      avg_latency_ms: avg(r.latency_ms),
      avg_cost_micro_usd: avg(r.cost_micro_usd)
    })
    |> Repo.all()
    |> Enum.group_by(& &1.skill_slug)
    |> Enum.map(fn {slug, rows} ->
      by_status = Map.new(rows, fn r -> {r.status, r.count} end)
      total = by_status |> Map.values() |> Enum.sum()
      done = Map.get(by_status, "done", 0)
      failed = Map.get(by_status, "failed", 0)

      %{
        skill_slug: slug,
        total: total,
        by_status: by_status,
        success_rate: if(total > 0, do: done / total, else: 0.0),
        failed: failed,
        avg_latency_ms: rows |> Enum.map(& &1.avg_latency_ms) |> avg_of_nullables(),
        avg_cost_micro_usd: rows |> Enum.map(& &1.avg_cost_micro_usd) |> avg_of_nullables()
      }
    end)
    |> Enum.sort_by(& &1.total, :desc)
  rescue
    _ -> []
  end

  @doc """
  Top failure modes attributed to each skill (joining
  `failure_occurrences.run_id` → `runs.skill_slug`).

  Shape:
      [%{skill_slug, total, by_mode: [%{slug, count}]}, ...]
  sorted by total desc.
  """
  def failures_by_skill(days \\ @default_days, per_skill \\ 5) do
    cutoff = cutoff(days)

    rows =
      from(o in FailureOccurrence,
        join: r in Run,
        on: r.id == o.run_id,
        left_join: m in FailureMode,
        on: m.id == o.failure_mode_id,
        where: o.inserted_at >= ^cutoff and not is_nil(r.skill_slug),
        group_by: [r.skill_slug, m.slug],
        select: %{
          skill_slug: r.skill_slug,
          mode_slug: m.slug,
          count: count(o.id)
        }
      )
      |> Repo.all()

    rows
    |> Enum.group_by(& &1.skill_slug)
    |> Enum.map(fn {slug, modes} ->
      modes_sorted =
        modes
        |> Enum.sort_by(& &1.count, :desc)
        |> Enum.take(per_skill)
        |> Enum.map(fn r -> %{slug: r.mode_slug, count: r.count} end)

      %{
        skill_slug: slug,
        total: modes |> Enum.map(& &1.count) |> Enum.sum(),
        by_mode: modes_sorted
      }
    end)
    |> Enum.sort_by(& &1.total, :desc)
  rescue
    _ -> []
  end

  # ----- 5c. Eval-run cost / latency aggregation -----

  @doc """
  Average cost (micro-USD) and latency (ms) of the trace `runs` rows
  that an eval run's cases executed. Used by the multi-signal
  auto-promote gate to compare baseline vs staging perf.

  Returns `%{avg_cost_micro_usd: float | nil, avg_latency_ms: float | nil,
  sample_size: int}`. `sample_size` is the number of cases whose
  underlying run row was found and aggregated — useful for callers
  who want to skip the gate when the sample is too thin to be
  meaningful (e.g. < 3 cases).

  Empty / missing eval ⇒ all keys nil, sample_size 0.
  """
  @spec eval_run_perf(binary() | nil) :: %{
          avg_cost_micro_usd: float() | nil,
          avg_latency_ms: float() | nil,
          sample_size: non_neg_integer()
        }
  def eval_run_perf(nil), do: empty_eval_perf()

  def eval_run_perf(eval_run_id) when is_binary(eval_run_id) do
    row =
      from(c in EvalCase,
        join: r in Run,
        on: r.id == c.run_id,
        where: c.eval_run_id == ^eval_run_id and not is_nil(c.run_id),
        select: %{
          avg_cost: avg(r.cost_micro_usd),
          avg_latency: avg(r.latency_ms),
          n: count(r.id)
        }
      )
      |> Repo.one()

    case row do
      %{n: n} when is_integer(n) and n > 0 ->
        %{
          avg_cost_micro_usd: to_float(row.avg_cost),
          avg_latency_ms: to_float(row.avg_latency),
          sample_size: n
        }

      _ ->
        empty_eval_perf()
    end
  rescue
    _ -> empty_eval_perf()
  end

  defp empty_eval_perf,
    do: %{avg_cost_micro_usd: nil, avg_latency_ms: nil, sample_size: 0}

  # ----- 6. Recent regressions -----

  @doc """
  Recently failed runs (status="failed") within the window. Sorted by
  `inserted_at` desc. Used as the regression alarm feed.

  Shape: `[%{id, user_input, status, inserted_at, latency_ms, errors}, ...]`
  """
  def recent_regressions(days \\ @default_days, limit \\ 10) do
    cutoff = cutoff(days)

    Run
    |> where([r], r.inserted_at >= ^cutoff and r.status == "failed")
    |> order_by([r], desc: r.inserted_at)
    |> limit(^limit)
    |> select([r], %{
      id: r.id,
      user_input: r.user_input,
      status: r.status,
      inserted_at: r.inserted_at,
      latency_ms: r.latency_ms,
      errors: r.errors
    })
    |> Repo.all()
  rescue
    _ -> []
  end

  # ----- Internals -----

  defp cutoff(days) when is_integer(days) and days > 0,
    do: DateTime.utc_now() |> DateTime.add(-days * 86_400, :second)

  defp cutoff(_), do: DateTime.utc_now() |> DateTime.add(-30 * 86_400, :second)

  defp to_float(nil), do: nil
  defp to_float(n) when is_number(n), do: n * 1.0
  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(_), do: nil

  defp avg_of_nullables(list) do
    nums = list |> Enum.map(&to_float/1) |> Enum.reject(&is_nil/1)

    case nums do
      [] -> nil
      _ -> Enum.sum(nums) / length(nums)
    end
  end
end
