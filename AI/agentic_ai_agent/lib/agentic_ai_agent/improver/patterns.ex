defmodule AgenticAiAgent.Improver.Patterns do
  @moduledoc """
  Cross-card learning for the Improver.

  ## The gap this closes

  Each card improves independently. If `card-A` benefitted from a
  `tightened_deny` proposal that lifted its eval score by +0.08, the
  Improver had to re-derive the same idea from scratch when proposing
  for `card-B`. Worse: a successful pattern can stay hidden behind a
  card slug, never surfaced to operators or to the LLM.

  This module:

    1. **Tags** new proposals with a coarse `pattern_tag` derived from
       the justification + root-cause text (`extract_pattern_tag/1`).
    2. **Lists** recently *applied* proposals with positive score
       deltas across all cards EXCEPT the one we're proposing for
       (`recent_successful/2`), so they can be surfaced as
       transferable hints in the next LLM call.
    3. **Tracks propagation** via `inspired_by_proposal_id` on the
       proposal — the LLM can cite a prior proposal in its JSON
       response, and the Improver validates + persists the link.

  Tags today (extend as patterns emerge):

    * `added_retrieval`       — surfaced when retrieval/RAG step added
    * `tightened_deny`        — narrowed tool_policy.deny
    * `tightened_allow`       — narrowed tool_policy.allow
    * `relaxed_allow`         — broadened tool_policy.allow
    * `added_reflexion`       — reflexion enabled / cadence tightened
    * `output_format_change`  — output_contract format/required fields
    * `prompt_clarify_goal`   — goal / role tightened
    * `skill_added`           — kind=skill_add
    * (returns nil when nothing matches)
  """

  import Ecto.Query

  alias AgenticAiAgent.Repo
  alias AgenticAiAgent.Improver.Proposal

  @default_recent_limit 6
  @default_window_days 60

  # ----- Tag extraction -----

  @doc """
  Map a proposal's narrative (justification + root_cause_summary) to a
  coarse `pattern_tag`. Returns `nil` when nothing matches — we'd
  rather leave the tag empty than invent a category.

  Special-cases by kind first so `skill_add` and `tool_policy_change`
  get high-precision tags before we fall back to keyword scanning.
  """
  @spec extract_pattern_tag(map() | Proposal.t() | nil) :: String.t() | nil
  def extract_pattern_tag(nil), do: nil

  def extract_pattern_tag(%{kind: "skill_add"}), do: "skill_added"

  def extract_pattern_tag(%{kind: "tool_policy_change", proposed_change: change})
      when is_map(change) do
    classify_tool_policy_change(change)
  end

  def extract_pattern_tag(%{} = proposal) do
    extract_from_text(text_for_tagging(proposal))
  end

  defp text_for_tagging(%{} = p) do
    [
      Map.get(p, :justification) || Map.get(p, "justification"),
      Map.get(p, :root_cause_summary) || Map.get(p, "root_cause_summary"),
      Map.get(p, :root_cause) || Map.get(p, "root_cause")
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.map(&to_string/1)
    |> Enum.join(" ")
  end

  defp classify_tool_policy_change(change) do
    # Best-effort heuristic — operators can spot-check via the UI.
    # We don't compare against the live card YAML here; the tag is
    # diagnostic, not load-bearing.
    cond do
      has_nonempty_list?(change, "deny") -> "tightened_deny"
      has_nonempty_list?(change, "allow") -> "tightened_allow"
      true -> nil
    end
  end

  defp has_nonempty_list?(change, key) do
    case Map.get(change, key) || Map.get(change, String.to_atom(key)) do
      list when is_list(list) and list != [] -> true
      _ -> false
    end
  end

  defp extract_from_text(""), do: nil

  defp extract_from_text(text) when is_binary(text) do
    lower = String.downcase(text)

    cond do
      String.match?(lower, ~r/\b(retriev\w*|rag|search before|added .* search)\b/) ->
        "added_retrieval"

      String.match?(
        lower,
        ~r/\b(tighten\w*|narrow\w*|restrict\w*|stricter)\b.*\b(deny|deni\w+)\b|\bdeny.*add(ed|s)?\b/
      ) ->
        "tightened_deny"

      String.match?(lower, ~r/\b(remove\w*|drop\w*)\b.*\b(allow)\b|\ballow.*shrink\w*\b/) ->
        "tightened_allow"

      String.match?(lower, ~r/\ballow\b.*(add\w*|expand\w*|broaden\w*|relax\w*)/) ->
        "relaxed_allow"

      String.match?(lower, ~r/\breflex\w*|self[- ]critic|reflection/) ->
        "added_reflexion"

      String.match?(
        lower,
        ~r/\b(output[- ]?format|output_contract|cite_sources|must_include|markdown)\b/
      ) ->
        "output_format_change"

      String.match?(
        lower,
        ~r/\b(clarif\w*|tighten\w*|specify\w*|sharpen\w*|reword\w*)\b.*\b(goal|role|prompt|scope)\b/
      ) ->
        "prompt_clarify_goal"

      true ->
        nil
    end
  end

  # ----- Queries -----

  @doc """
  Recently applied proposals with positive score_delta, excluding the
  given slug. Used to surface "what worked elsewhere" in the Improver
  prompt.

  Returns `[%{id, target, kind, pattern_tag, score_delta, justification,
  applied_at, root_cause_summary}]` sorted by score_delta desc.

  Opts:
    * `:limit` — max rows (default #{@default_recent_limit})
    * `:days` — lookback window in days (default #{@default_window_days})
  """
  @spec recent_successful(String.t() | nil, keyword()) :: [map()]
  def recent_successful(exclude_slug \\ nil, opts \\ [])

  def recent_successful(exclude_slug, opts) do
    limit = Keyword.get(opts, :limit, @default_recent_limit)
    days = Keyword.get(opts, :days, @default_window_days)
    cutoff = DateTime.utc_now() |> DateTime.add(-days * 86_400, :second)

    base =
      from p in Proposal,
        where:
          p.status == "applied" and
            not is_nil(p.score_delta) and p.score_delta > 0.0 and
            (is_nil(p.applied_at) or p.applied_at >= ^cutoff),
        order_by: [desc: p.score_delta],
        limit: ^limit,
        select: %{
          id: p.id,
          target: p.target,
          kind: p.kind,
          pattern_tag: p.pattern_tag,
          score_delta: p.score_delta,
          justification: p.justification,
          applied_at: p.applied_at,
          root_cause_summary: p.root_cause_summary
        }

    query =
      case exclude_slug do
        slug when is_binary(slug) and slug != "" -> where(base, [p], p.target != ^slug)
        _ -> base
      end

    Repo.all(query)
  rescue
    _ -> []
  end

  # ----- Linkage validation -----

  @doc """
  Validate an `inspired_by` id supplied by the LLM. Returns the id when
  it points at an existing proposal that is itself `applied` with a
  positive score_delta (the only proposals it makes sense to learn
  from); returns `nil` otherwise. Pure DB read.
  """
  @spec validate_inspired_by(binary() | nil) :: binary() | nil
  def validate_inspired_by(nil), do: nil
  def validate_inspired_by(""), do: nil

  def validate_inspired_by(id) when is_binary(id) do
    Repo.one(
      from(p in Proposal,
        where:
          p.id == ^id and p.status == "applied" and
            not is_nil(p.score_delta) and p.score_delta > 0.0,
        select: p.id,
        limit: 1
      )
    )
  rescue
    _ -> nil
  end
end
