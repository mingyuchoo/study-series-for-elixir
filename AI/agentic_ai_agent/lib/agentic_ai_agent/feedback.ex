defmodule AgenticAiAgent.Feedback do
  @moduledoc """
  Turn human "this answer was wrong" feedback into golden-dataset rows so
  the next eval cycle catches the regression.

  Two roles:

    * **flag** — called from the chat UI when the user clicks 👎 on the
      final assistant answer. Snapshots the run's `user_input` and
      `final_answer` into a `golden_candidates` row (status=pending).

    * **promote** — called from the curation page when an operator has
      filled in a `corrected_answer`. Appends a JSONL row to
      `priv/eval/golden/regressions.jsonl` and marks the candidate
      `promoted`.

  Cards that want to be checked against regressions can point their
  `evaluation_mapping.golden_dataset` at `priv/eval/golden/regressions.jsonl`
  (in addition to their normal golden), or use
  `mix agent.eval --card <slug> --golden priv/eval/golden/regressions.jsonl`
  ad-hoc.
  """

  import Ecto.Query

  alias AgenticAiAgent.Repo
  alias AgenticAiAgent.Feedback.GoldenCandidate
  alias AgenticAiAgent.Traces

  @regressions_relpath "priv/eval/golden/regressions.jsonl"

  # ----- Read -----

  @spec list(keyword()) :: [GoldenCandidate.t()]
  def list(opts \\ []) do
    status = Keyword.get(opts, :status)
    limit = Keyword.get(opts, :limit, 100)

    GoldenCandidate
    |> maybe_status(status)
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  defp maybe_status(q, nil), do: q
  defp maybe_status(q, status), do: where(q, status: ^status)

  def get!(id), do: Repo.get!(GoldenCandidate, id)

  def count_pending,
    do: Repo.aggregate(from(c in GoldenCandidate, where: c.status == "pending"), :count, :id)

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
  def flag(run_id, opts \\ []) when is_binary(run_id) do
    try do
      run = Traces.get_run!(run_id)

      attrs = %{
        run_id: run.id,
        user_input: run.user_input || "",
        assistant_answer: run.final_answer,
        target_card_slug: Keyword.get(opts, :target_card_slug),
        user_note: Keyword.get(opts, :user_note),
        flagged_by: Keyword.get(opts, :flagged_by, "chat-user"),
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
  def flag_from_judge(run, card, %{score: score, reason: reason} = _judgment)
      when is_map(run) do
    run_id = Map.get(run, :id)

    case existing_judge_candidate(run_id) do
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
          status: "pending"
        }

        %GoldenCandidate{}
        |> GoldenCandidate.changeset(attrs)
        |> Repo.insert()
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp existing_judge_candidate(nil), do: nil

  defp existing_judge_candidate(run_id) do
    GoldenCandidate
    |> where([c], c.run_id == ^run_id and c.flagged_by == "judge")
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

  def promote!(%GoldenCandidate{} = c, opts) do
    corrected = Keyword.get(opts, :corrected_answer) || c.corrected_answer

    cond do
      corrected in [nil, ""] ->
        {:error, :corrected_answer_required}

      true ->
        path = absolute_regressions_path()
        line = jsonl_line(c, corrected)

        with :ok <- File.mkdir_p(Path.dirname(path)),
             :ok <- File.write(path, line <> "\n", [:append]) do
          updated =
            c
            |> GoldenCandidate.changeset(%{
              status: "promoted",
              corrected_answer: corrected,
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

  defp absolute_regressions_path do
    Application.app_dir(:agentic_ai_agent, @regressions_relpath)
  end

  defp relative_path(absolute) when is_binary(absolute) do
    case String.split(absolute, "/priv/", parts: 2) do
      [_, rest] -> "priv/" <> rest
      _ -> absolute
    end
  end

  # Build a single JSONL row matching the existing dataset shape:
  #   {"id": "...", "task_type": "regression", "input": "...",
  #    "expected": {"final_answer_contains": "..."}, "max_steps": 12}
  defp jsonl_line(%GoldenCandidate{id: id} = c, corrected) do
    short = id |> String.slice(0, 8)

    payload = %{
      "id" => "regression-#{short}",
      "task_type" => "regression",
      "input" => c.user_input,
      "expected" => %{"final_answer_contains" => corrected},
      "max_steps" => 12,
      "source" => %{
        "candidate_id" => id,
        "run_id" => c.run_id,
        "flagged_at" => c.inserted_at
      }
    }

    Jason.encode!(payload)
  end
end
