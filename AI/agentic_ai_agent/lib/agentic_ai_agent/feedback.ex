defmodule AgenticAiAgent.Feedback do
  @moduledoc """
  Turn human feedback into golden-dataset rows so the next eval cycle
  either catches a regression or confirms a "do more of this" target.

  ## Symmetric polarities

    * **negative (👎 / judge low score)** — `flag/2` snapshots the run
      into a `golden_candidates` row with `polarity="negative"` and
      `status="pending"`. `promote!/2` requires a `corrected_answer` and
      appends to `priv/eval/golden/regressions.jsonl`.

    * **positive (👍 / judge high score)** — `praise/2` does the same
      with `polarity="positive"`. `promote!/2` does NOT require a
      corrected_answer (the assistant's original answer IS the gold)
      and appends to `priv/eval/golden/wins.jsonl`.

  Both polarities flow through the same operator-curation page
  (`/feedback`) and the same Improver context — the Improver sees what
  worked AND what didn't, so it can both fix regressions and avoid
  proposing changes that would break a praised pattern.

  Cards that want to be evaluated against either dataset point their
  `evaluation_mapping.golden_dataset` at the corresponding JSONL.
  """

  import Ecto.Query

  alias AgenticAiAgent.Repo
  alias AgenticAiAgent.Feedback.GoldenCandidate
  alias AgenticAiAgent.Traces

  @regressions_relpath "priv/eval/golden/regressions.jsonl"
  @wins_relpath "priv/eval/golden/wins.jsonl"

  # ----- Read -----

  @spec list(keyword()) :: [GoldenCandidate.t()]
  def list(opts \\ []) do
    status = Keyword.get(opts, :status)
    polarity = Keyword.get(opts, :polarity)
    target_slug = Keyword.get(opts, :target_card_slug)
    limit = Keyword.get(opts, :limit, 100)

    GoldenCandidate
    |> maybe_status(status)
    |> maybe_polarity(polarity)
    |> maybe_target(target_slug)
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  defp maybe_status(q, nil), do: q
  defp maybe_status(q, status), do: where(q, status: ^status)

  defp maybe_polarity(q, nil), do: q
  defp maybe_polarity(q, polarity), do: where(q, polarity: ^polarity)

  defp maybe_target(q, nil), do: q
  defp maybe_target(q, slug), do: where(q, target_card_slug: ^slug)

  def get!(id), do: Repo.get!(GoldenCandidate, id)

  def count_pending,
    do: Repo.aggregate(from(c in GoldenCandidate, where: c.status == "pending"), :count, :id)

  @doc "Pending counts split by polarity, returns `%{\"negative\" => n, \"positive\" => m}`."
  def count_pending_by_polarity do
    from(c in GoldenCandidate, where: c.status == "pending", group_by: c.polarity)
    |> select([c], {c.polarity, count(c.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Recent positive candidates (👍 or judge-praised) for a card,
  optionally restricted to promoted ones. Used by `Improver` to
  surface "what's working — don't break this" in the proposer prompt.
  """
  @spec recent_positive_for_card(String.t() | nil, keyword()) :: [GoldenCandidate.t()]
  def recent_positive_for_card(card_slug, opts \\ [])
  def recent_positive_for_card(nil, _opts), do: []

  def recent_positive_for_card(card_slug, opts) when is_binary(card_slug) do
    limit = Keyword.get(opts, :limit, 5)
    statuses = Keyword.get(opts, :statuses, ["pending", "promoted"])

    GoldenCandidate
    |> where([c], c.target_card_slug == ^card_slug and c.polarity == "positive")
    |> where([c], c.status in ^statuses)
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> Repo.all()
  rescue
    _ -> []
  end

  # ----- Flag -----

  @doc """
  Snapshot a run as a pending golden candidate. Pulls `user_input` and
  `final_answer` from the run row. Refuses runs that haven't produced a
  final answer (status must be `done` or `failed`).

  Options:
    * `:user_note` — short free-form note from the chat user
    * `:flagged_by` — caller identity (defaults to "chat-user")
    * `:target_card_slug` — card the run was using (snapshot)
  """
  @spec flag(binary(), keyword()) ::
          {:ok, GoldenCandidate.t()} | {:error, term()}
  def flag(run_id, opts \\ []) when is_binary(run_id), do: snapshot(run_id, "negative", opts)

  @doc """
  Symmetric counterpart of `flag/2` — snapshot a run as a *positive*
  golden candidate. Triggered from the chat UI when the user clicks
  👍, or auto-fired by the judge on high scores.

  Same options as `flag/2`. The resulting row has `polarity="positive"`
  and `status="pending"`; promoting it writes to `wins.jsonl`.
  """
  @spec praise(binary(), keyword()) ::
          {:ok, GoldenCandidate.t()} | {:error, term()}
  def praise(run_id, opts \\ []) when is_binary(run_id), do: snapshot(run_id, "positive", opts)

  defp snapshot(run_id, polarity, opts) do
    try do
      run = Traces.get_run!(run_id)

      attrs = %{
        run_id: run.id,
        user_input: run.user_input || "",
        assistant_answer: run.final_answer,
        target_card_slug: Keyword.get(opts, :target_card_slug),
        user_note: Keyword.get(opts, :user_note),
        flagged_by: Keyword.get(opts, :flagged_by, "chat-user"),
        polarity: polarity,
        status: "pending"
      }

      %GoldenCandidate{}
      |> GoldenCandidate.changeset(attrs)
      |> Repo.insert()
    rescue
      Ecto.NoResultsError -> {:error, :run_not_found}
      e -> {:error, Exception.message(e)}
    end
  end

  @doc """
  Variant of `flag/2` used by the LLM-as-judge auto-flagger. Idempotent
  per run + flagged_by="judge": if a judge-created candidate already exists
  for the run, returns `{:already_flagged, existing}` instead of inserting
  a duplicate.

  The judge's score and reason are stored alongside the snapshot so an
  operator on `/feedback` can sort/filter by judge_score and read why.
  """
  @spec flag_from_judge(map(), map() | nil, map()) ::
          {:ok, GoldenCandidate.t()}
          | {:already_flagged, GoldenCandidate.t()}
          | {:error, term()}
  def flag_from_judge(run, card, judgment), do: judge_snapshot(run, card, judgment, "negative")

  @doc """
  Symmetric counterpart of `flag_from_judge/3` — auto-praise on a high
  judge score. Same idempotency rule (one judge row per (run, polarity)).
  """
  @spec praise_from_judge(map(), map() | nil, map()) ::
          {:ok, GoldenCandidate.t()}
          | {:already_flagged, GoldenCandidate.t()}
          | {:error, term()}
  def praise_from_judge(run, card, judgment),
    do: judge_snapshot(run, card, judgment, "positive")

  defp judge_snapshot(run, card, %{score: score, reason: reason}, polarity) when is_map(run) do
    run_id = Map.get(run, :id)

    case existing_judge_candidate(run_id, polarity) do
      %GoldenCandidate{} = existing ->
        {:already_flagged, existing}

      nil ->
        attrs = %{
          run_id: run_id,
          user_input: Map.get(run, :user_input) || "",
          assistant_answer: Map.get(run, :final_answer),
          target_card_slug: card && Map.get(card, :slug),
          user_note: "judge: #{reason}",
          flagged_by: "judge",
          judge_score: score,
          polarity: polarity,
          status: "pending"
        }

        %GoldenCandidate{}
        |> GoldenCandidate.changeset(attrs)
        |> Repo.insert()
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp existing_judge_candidate(nil, _polarity), do: nil

  defp existing_judge_candidate(run_id, polarity) do
    GoldenCandidate
    |> where(
      [c],
      c.run_id == ^run_id and c.flagged_by == "judge" and c.polarity == ^polarity
    )
    |> limit(1)
    |> Repo.one()
  end

  # ----- Promote -----

  @doc """
  Promote a candidate into the regressions golden file. Requires
  `corrected_answer` to be present (either in the candidate row or in
  `opts[:corrected_answer]` — the latter wins). Appends a JSONL row,
  then marks the candidate `promoted`.

  Returns `{:ok, candidate}` on success or `{:error, reason}` on
  validation/IO failure. Already-promoted candidates return
  `{:error, :already_promoted}`.
  """
  @spec promote!(GoldenCandidate.t(), keyword()) ::
          {:ok, GoldenCandidate.t()} | {:error, term()}
  def promote!(%GoldenCandidate{status: "promoted"}, _opts),
    do: {:error, :already_promoted}

  def promote!(%GoldenCandidate{polarity: "positive"} = c, opts) do
    # Positives: the original answer IS the gold. We require that the
    # snapshot captured an assistant_answer — without it there's nothing
    # to assert against in the eval.
    case c.assistant_answer do
      ans when ans in [nil, ""] ->
        {:error, :empty_assistant_answer}

      _ ->
        write_and_mark(c, absolute_wins_path(), c.assistant_answer, opts)
    end
  end

  def promote!(%GoldenCandidate{} = c, opts) do
    corrected = Keyword.get(opts, :corrected_answer) || c.corrected_answer

    case corrected do
      v when v in [nil, ""] -> {:error, :corrected_answer_required}
      _ -> write_and_mark(c, absolute_regressions_path(), corrected, opts)
    end
  end

  defp write_and_mark(%GoldenCandidate{} = c, path, expected_text, opts) do
    line = jsonl_line(c, expected_text)

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, line <> "\n", [:append]) do
      updated =
        c
        |> GoldenCandidate.changeset(%{
          status: "promoted",
          corrected_answer:
            if(c.polarity == "positive", do: c.corrected_answer, else: expected_text),
          promoted_to_path: relative_path(path),
          promoted_at: DateTime.utc_now() |> DateTime.truncate(:second),
          promoted_by: Keyword.get(opts, :by, "hitl-user")
        })
        |> Repo.update!()

      {:ok, updated}
    else
      err -> {:error, err}
    end
  end

  # ----- Dismiss -----

  @doc """
  Mark a candidate as dismissed (operator decided it's not worth adding
  to the regression set). Optional reason captured for audit.
  """
  @spec dismiss!(GoldenCandidate.t(), keyword()) :: GoldenCandidate.t()
  def dismiss!(%GoldenCandidate{} = c, opts \\ []) do
    c
    |> GoldenCandidate.changeset(%{
      status: "dismissed",
      dismissed_reason: Keyword.get(opts, :reason),
      promoted_by: Keyword.get(opts, :by, "hitl-user")
    })
    |> Repo.update!()
  end

  # ----- Helpers -----

  def regressions_path, do: absolute_regressions_path()
  def wins_path, do: absolute_wins_path()

  defp absolute_regressions_path,
    do: Application.app_dir(:agentic_ai_agent, @regressions_relpath)

  defp absolute_wins_path,
    do: Application.app_dir(:agentic_ai_agent, @wins_relpath)

  defp relative_path(absolute) when is_binary(absolute) do
    case String.split(absolute, "/priv/", parts: 2) do
      [_, rest] -> "priv/" <> rest
      _ -> absolute
    end
  end

  # Build a single JSONL row. Negative candidates produce
  # `task_type=regression`, positives produce `task_type=win`. Both
  # express the expected answer as `final_answer_contains` so the
  # existing scorer can grade either dataset without changes.
  defp jsonl_line(%GoldenCandidate{id: id, polarity: polarity} = c, expected_text) do
    short = id |> String.slice(0, 8)

    {prefix, task_type} =
      if polarity == "positive", do: {"win", "win"}, else: {"regression", "regression"}

    payload = %{
      "id" => "#{prefix}-#{short}",
      "task_type" => task_type,
      "input" => c.user_input,
      "expected" => %{"final_answer_contains" => expected_text},
      "max_steps" => 12,
      "source" => %{
        "candidate_id" => id,
        "run_id" => c.run_id,
        "polarity" => polarity,
        "flagged_at" => c.inserted_at
      }
    }

    Jason.encode!(payload)
  end
end
