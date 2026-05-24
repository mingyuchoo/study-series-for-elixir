defmodule AgenticAiAgent.Agent.ReflexionInsights do
  @moduledoc """
  Bridges the in-flight self-critic (`AgenticAiAgent.Agent.Reflexion`) to
  the meta-improver (`AgenticAiAgent.Improver`).

  ## The gap this closes

  Reflexion produces a critique on every run, but those critiques are
  advisory — they're injected into the next planning turn and that's
  it. A *recurring* weakness ("the agent keeps skipping retrieve before
  tool calls") never becomes a concrete proposal because nothing
  remembers the pattern across runs.

  This module records each critique as a `reflexion_insights` row
  tagged with a coarse `theme` (extracted heuristically from the
  critique text — no LLM call needed). When the count of recent
  insights sharing a theme on the same card crosses a threshold
  (default 3), we:

    1. Emit a `"reflexion_saturation"` notification — the operator
       sees there's a recurring weakness worth proposing a fix for.
    2. Surface the recurring themes in `Improver.build_context/2`, so
       the next proposal generation actively targets the pattern.

  The theme extractor is intentionally simple keyword matching. It's
  better to under-classify (theme=nil) than to invent a category that
  isn't really there — operators can spot-check via the LiveView.
  """

  import Ecto.Query

  alias AgenticAiAgent.Agent.ReflexionInsights.Insight
  alias AgenticAiAgent.{Notifications, Repo}

  require Logger

  @default_saturation_threshold 3
  @default_recent_window_days 14
  @default_per_card_limit 20

  # ----- Recording -----

  @doc """
  Persist one critique. Idempotency: if the run already has an insight
  row, returns the existing one (avoids dupes on runtime restart).

  On saturation (the threshold is freshly crossed), emits a
  `"reflexion_saturation"` notification. The threshold is read from
  application config:

      config :agentic_ai_agent, AgenticAiAgent.Agent.ReflexionInsights,
        saturation_threshold: 3

  Returns `{:ok, insight, :new | :existing}` or `{:error, reason}`.
  Callers should treat errors as advisory — failure to record an
  insight must never break the parent run.
  """
  @spec record(map() | nil, map() | nil, String.t() | nil) ::
          {:ok, Insight.t(), :new | :existing} | {:error, term()}
  def record(_run, _card, critique) when critique in [nil, ""],
    do: {:error, :empty_critique}

  def record(run, card, critique) when is_binary(critique) do
    run_id = run && Map.get(run, :id)
    card_slug = card && Map.get(card, :slug)
    theme = extract_theme(critique)

    case existing_for_run(run_id) do
      %Insight{} = existing ->
        {:ok, existing, :existing}

      nil ->
        attrs = %{
          run_id: run_id,
          card_slug: card_slug,
          critique: String.slice(critique, 0, 4_000),
          theme: theme
        }

        case %Insight{} |> Insight.changeset(attrs) |> Repo.insert() do
          {:ok, insight} ->
            _ = maybe_emit_saturation(card_slug, theme)
            {:ok, insight, :new}

          {:error, cs} ->
            {:error, cs}
        end
    end
  rescue
    e ->
      Logger.warning("ReflexionInsights.record/3 crashed: #{Exception.message(e)}")
      {:error, Exception.message(e)}
  end

  defp existing_for_run(nil), do: nil

  defp existing_for_run(run_id) when is_binary(run_id) do
    Repo.one(from(i in Insight, where: i.run_id == ^run_id, limit: 1))
  end

  # Saturation triggers exactly when the NEW row pushes the recent
  # count for a (slug, theme) pair up TO the threshold — not above it.
  # Otherwise the operator would get re-pinged on every subsequent run.
  defp maybe_emit_saturation(nil, _), do: :ok
  defp maybe_emit_saturation(_, nil), do: :ok

  defp maybe_emit_saturation(card_slug, theme) do
    threshold = saturation_threshold()
    count = count_recent_for_theme(card_slug, theme)

    if count == threshold do
      _ =
        Notifications.emit("reflexion_saturation",
          subject: "Recurring self-critique on #{card_slug}: #{theme} (×#{count})",
          body:
            "The self-critic has flagged the same kind of weakness " <>
              "(#{theme}) in #{count} recent runs of `#{card_slug}`. " <>
              "Next Improver tick will see this as a target.",
          card_slug: card_slug
        )
    end

    :ok
  end

  # ----- Queries -----

  @doc """
  Recent insights for a card, newest first.

  Opts:
    * `:limit` — default #{@default_per_card_limit}
    * `:days`  — lookback window, default #{@default_recent_window_days}
  """
  @spec recent_for_card(String.t() | nil, keyword()) :: [Insight.t()]
  def recent_for_card(card_slug, opts \\ [])
  def recent_for_card(nil, _opts), do: []

  def recent_for_card(card_slug, opts) when is_binary(card_slug) do
    limit = Keyword.get(opts, :limit, @default_per_card_limit)
    days = Keyword.get(opts, :days, @default_recent_window_days)
    cutoff = days_ago(days)

    from(i in Insight,
      where: i.card_slug == ^card_slug and i.inserted_at >= ^cutoff,
      order_by: [desc: i.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  rescue
    _ -> []
  end

  @doc """
  Group recent insights for a card by theme; return only themes whose
  count meets the saturation threshold. Used by
  `Improver.build_context/2` to surface "what is this card repeatedly
  flagging itself for?".

  Returns `[%{theme, count, sample_critique, latest_at, run_ids}]`,
  sorted by count desc.
  """
  @spec recurring_themes_for_card(String.t() | nil, keyword()) :: [map()]
  def recurring_themes_for_card(card_slug, opts \\ [])
  def recurring_themes_for_card(nil, _opts), do: []

  def recurring_themes_for_card(card_slug, opts) when is_binary(card_slug) do
    threshold = Keyword.get(opts, :threshold, saturation_threshold())
    days = Keyword.get(opts, :days, @default_recent_window_days)
    cutoff = days_ago(days)

    rows =
      from(i in Insight,
        where:
          i.card_slug == ^card_slug and not is_nil(i.theme) and
            i.inserted_at >= ^cutoff,
        order_by: [desc: i.inserted_at]
      )
      |> Repo.all()

    rows
    |> Enum.group_by(& &1.theme)
    |> Enum.map(fn {theme, items} ->
      %{
        theme: theme,
        count: length(items),
        sample_critique: items |> List.first() |> Map.get(:critique) |> String.slice(0, 240),
        latest_at: items |> List.first() |> Map.get(:inserted_at),
        run_ids: items |> Enum.map(& &1.run_id) |> Enum.reject(&is_nil/1)
      }
    end)
    |> Enum.filter(&(&1.count >= threshold))
    |> Enum.sort_by(& &1.count, :desc)
  rescue
    _ -> []
  end

  defp count_recent_for_theme(card_slug, theme) do
    cutoff = days_ago(@default_recent_window_days)

    Repo.one(
      from(i in Insight,
        where:
          i.card_slug == ^card_slug and i.theme == ^theme and
            i.inserted_at >= ^cutoff,
        select: count(i.id)
      )
    ) || 0
  end

  # ----- Linkage (Improver attribution) -----

  @doc """
  Mark all insights matching `(card_slug, themes)` within the recent
  window as having triggered `proposal_id`. The operator can later
  audit which reflexions caused which proposal.

  No-op if either arg is empty. Returns the number of rows updated.
  """
  @spec link_proposal!(String.t() | nil, [String.t()], binary() | nil) ::
          non_neg_integer()
  def link_proposal!(nil, _themes, _id), do: 0
  def link_proposal!(_slug, [], _id), do: 0
  def link_proposal!(_slug, _themes, nil), do: 0

  def link_proposal!(card_slug, themes, proposal_id)
      when is_binary(card_slug) and is_list(themes) and is_binary(proposal_id) do
    cutoff = days_ago(@default_recent_window_days)

    {n, _} =
      from(i in Insight,
        where:
          i.card_slug == ^card_slug and i.theme in ^themes and
            i.inserted_at >= ^cutoff and is_nil(i.triggered_proposal_id)
      )
      |> Repo.update_all(set: [triggered_proposal_id: proposal_id])

    n
  end

  # ----- Theme extraction (heuristic) -----

  @doc """
  Map a critique text to a coarse theme via case-insensitive keyword
  matching. Returns `nil` when no pattern matches — better to
  under-classify than to invent a category. The returned theme keys
  are stable strings the LLM proposer can be told about.

  Themes today (extend as patterns emerge):

    * `"tool_misuse"`      — keywords about wrong/missing tool usage
    * `"missing_retrieve"` — flags skipping retrieval before acting
    * `"off_topic"`        — drifting from the user's question
    * `"incomplete"`       — answer missing required content
    * `"hallucination"`    — making things up / unsupported claims
    * `"looping"`          — repeating the same step / no progress
    * `"premature_final"`  — answering before doing the work

  Order matters: more specific patterns are checked before more
  general ones.
  """
  @spec extract_theme(String.t() | nil) :: String.t() | nil
  def extract_theme(nil), do: nil
  def extract_theme(""), do: nil

  def extract_theme(text) when is_binary(text) do
    lower = String.downcase(text)

    cond do
      # "skipped retrieve", "missing search context", "no rag step", etc.
      String.match?(
        lower,
        ~r/\b(skip\w*|miss\w*|no)\b.*\b(retriev\w*|search\w*|context|rag)\b/
      ) ->
        "missing_retrieve"

      String.match?(
        lower,
        ~r/\b(wrong|misuse|bad input|invalid arg)\w*.*\btool\w*\b|\btool\w*.*\b(wrong|misuse|empty|bad)\w*\b/
      ) ->
        "tool_misuse"

      String.match?(lower, ~r/\b(off[- ]topic|drift\w*|irrelevant|unrelated)\b/) ->
        "off_topic"

      String.match?(lower, ~r/\b(hallucinat\w*|fabricat\w*|made up|unsupported|no evidence)\b/) ->
        "hallucination"

      String.match?(lower, ~r/\b(loop\w*|repeat\w*|no progress|stuck)\b/) ->
        "looping"

      String.match?(lower, ~r/\b(prematur\w*|too early|jumped to|finalized before)\b/) ->
        "premature_final"

      String.match?(lower, ~r/\b(incomplete|missing detail|not enough|partial)\b/) ->
        "incomplete"

      true ->
        nil
    end
  end

  # ----- Internals -----

  defp saturation_threshold do
    Application.get_env(:agentic_ai_agent, __MODULE__, [])
    |> Keyword.get(:saturation_threshold, @default_saturation_threshold)
  end

  defp days_ago(n) when is_integer(n) and n > 0,
    do: DateTime.utc_now() |> DateTime.add(-n * 86_400, :second)

  defp days_ago(_),
    do: DateTime.utc_now() |> DateTime.add(-@default_recent_window_days * 86_400, :second)
end
