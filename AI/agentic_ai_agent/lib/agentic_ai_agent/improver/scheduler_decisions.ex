defmodule AgenticAiAgent.Improver.SchedulerDecisions do
  @moduledoc """
  Audit log for `AgenticAiAgent.Improver.Scheduler` decisions.

  Every time the scheduler considers a staging eval result it records
  one row here, regardless of whether the decision was a real mutation
  (auto-promote, auto-rollback) or a dry-run preview. This makes
  autonomous behavior observable:

    * the operator can answer "what did the scheduler do this week?"
      from one table
    * dry-run telemetry lives alongside real telemetry so the only
      difference between modes is the `dry_run` flag — `summary/1`
      groups by both action and mode
    * gate-block records show *why* a proposal didn't make it through
      auto-promote (safety verdict, perf ratio) without scrolling
      through notifications

  Designed to coexist with `AgenticAiAgent.Notifications`: notifications
  are operator alerts (mark-read, expire), decisions are a permanent
  audit trail.
  """

  import Ecto.Query
  require Logger

  alias AgenticAiAgent.Repo
  alias AgenticAiAgent.Improver.SchedulerDecisions.Decision

  @default_window_days 30
  @default_limit 200

  # ----- Write -----

  @doc """
  Record one decision. `action` must be one of `Decision.actions/0`.

  Opts:
    * `:dry_run` — boolean, default false
    * `:card_slug` — string
    * `:proposal_id` — proposal binary_id (nullable for global decisions)
    * `:detail` — short human summary
    * `:metadata` — free-form JSON-friendly map

  Returns `{:ok, decision}` or `{:error, reason}`. Failure to persist
  must never break the scheduler — callers should ignore the return
  value.
  """
  @spec record(String.t(), keyword()) :: {:ok, Decision.t()} | {:error, term()}
  def record(action, opts \\ []) when is_binary(action) do
    attrs =
      opts
      |> Map.new()
      |> Map.put(:action, action)

    %Decision{}
    |> Decision.changeset(attrs)
    |> Repo.insert()
  rescue
    e ->
      Logger.warning("SchedulerDecisions.record/2 failed: #{Exception.message(e)}")
      {:error, Exception.message(e)}
  end

  # ----- Read -----

  @doc """
  List recent decisions, newest first.

  Opts:
    * `:limit` — default #{@default_limit}
    * `:action` — filter by action string
    * `:card_slug` — filter by card
    * `:dry_run` — `true` for dry-run only, `false` for real only,
      omit for both
  """
  @spec list(keyword()) :: [Decision.t()]
  def list(opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)

    Decision
    |> maybe_filter(:action, Keyword.get(opts, :action))
    |> maybe_filter(:card_slug, Keyword.get(opts, :card_slug))
    |> maybe_filter(:dry_run, Keyword.get(opts, :dry_run))
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> Repo.all()
  rescue
    _ -> []
  end

  defp maybe_filter(q, _key, nil), do: q
  defp maybe_filter(q, key, value), do: where(q, ^[{key, value}])

  @doc """
  Aggregate decisions over the last `days` (default 30) into a counts
  map keyed by `{action, dry_run}`. Useful as a one-glance dashboard:
  "the scheduler made N applies, M rollbacks, K safety blocks this
  month."

  Returns `%{{action, dry_run} => count}`. Action keys mirror
  `Decision.actions/0`.
  """
  @spec summary(integer()) :: %{{String.t(), boolean()} => non_neg_integer()}
  def summary(days \\ @default_window_days) when is_integer(days) and days > 0 do
    cutoff = DateTime.utc_now() |> DateTime.add(-days * 86_400, :second)

    Decision
    |> where([d], d.inserted_at >= ^cutoff)
    |> group_by([d], [d.action, d.dry_run])
    |> select([d], {{d.action, d.dry_run}, count(d.id)})
    |> Repo.all()
    |> Map.new()
  rescue
    _ -> %{}
  end
end
