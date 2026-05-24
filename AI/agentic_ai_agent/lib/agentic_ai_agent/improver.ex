defmodule AgenticAiAgent.Improver do
  @moduledoc """
  Meta-agent that reads aggregated traces, failures, and eval scores to
  propose ONE concrete change to an Agentic Card YAML. Proposals are
  persisted in `improvement_proposals` and never auto-applied: an operator
  must Approve and then Apply via the `/improvements` LiveView.

  Lifecycle:

      build_context(slug) → %Context{}
      generate_proposal(slug) → {:ok, %Proposal{}} | {:error, _}
      approve!(proposal, by)
      reject!(proposal, by, reason)
      apply!(proposal, by) → writes via Design.save_card_source (which
         auto-snapshots a version row from Phase 2, so rollback is free)

  Safety: this module never modifies cards on its own. Every change to a
  YAML file requires an `apply!/2` call which is only enabled after
  `approve!/2`.
  """

  import Ecto.Query

  alias AgenticAiAgent.{Analytics, Design, Eval, Failures, LLM, Repo}
  alias AgenticAiAgent.Eval.EvalRun
  alias AgenticAiAgent.Improver.Proposal
  alias AgenticAiAgent.LLM.Response

  @default_recent_failures 50
  @default_window_days 30
  @default_top_supporting 5

  # ----- Queries (HITL queue surface) -----

  @doc "All proposals, newest first."
  def list_proposals(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    status = Keyword.get(opts, :status)

    Proposal
    |> maybe_status(status)
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  defp maybe_status(q, nil), do: q
  defp maybe_status(q, status), do: where(q, status: ^status)

  def get_proposal!(id), do: Repo.get!(Proposal, id)

  def count_pending,
    do: Repo.aggregate(from(p in Proposal, where: p.status == "pending"), :count, :id)

  @doc """
  Count of LLM-call activity *today* (UTC). Used by the autonomous
  scheduler to enforce a daily proposal cap. A row counts whether or
  not it was malformed/applied — every generation = one call.
  """
  def count_today do
    today = DateTime.utc_now() |> DateTime.add(-86_400, :second)
    Repo.aggregate(from(p in Proposal, where: p.inserted_at >= ^today), :count, :id)
  end

  @doc """
  Count of `apply!` actions performed today (UTC). Used to enforce a
  daily mutation cap on the autonomous scheduler.
  """
  def count_applied_today do
    today = DateTime.utc_now() |> DateTime.add(-86_400, :second)

    Repo.aggregate(
      from(p in Proposal, where: p.applied_at >= ^today),
      :count,
      :id
    )
  end

  @doc """
  Find the CardVersion row whose body was on disk immediately before the
  given applied proposal wrote its own version. Used for auto-rollback.

  Returns `nil` if no previous version exists.
  """
  def find_previous_card_version(%Proposal{kind: "card_edit", target: slug, applied_at: applied_at})
      when not is_nil(applied_at) do
    AgenticAiAgent.Design.list_card_versions(slug)
    |> Enum.find(fn v -> DateTime.compare(v.inserted_at, applied_at) == :lt end)
  end

  def find_previous_card_version(_), do: nil

  @doc """
  Mark a proposal as rolled back (records reason + timestamp). Does NOT
  perform the restore — caller has already done so.
  """
  def mark_rolled_back!(%Proposal{} = p, reason) when is_binary(reason) do
    p
    |> Proposal.changeset(%{
      rolled_back_at: DateTime.utc_now() |> DateTime.truncate(:second),
      rolled_back_reason: reason
    })
    |> Repo.update!()
  end

  @doc """
  Internal helper for the Scheduler: bump auto_promoted=true on the row.
  """
  def mark_auto_promoted!(%Proposal{} = p) do
    p
    |> Proposal.changeset(%{auto_promoted: true})
    |> Repo.update!()
  end

  # ----- Public API: produce a proposal -----

  @doc """
  Gather the meta-agent's context for a given card slug. Pure read-only;
  no LLM call, no DB write. Useful for tests and the "preview prompt" UI.
  """
  @spec build_context(String.t(), keyword()) :: map()
  def build_context(slug, opts \\ []) when is_binary(slug) do
    days = Keyword.get(opts, :days, @default_window_days)

    %{
      slug: slug,
      window_days: days,
      run_health: Analytics.run_health(days),
      failures_by_mode: Analytics.failures_by_mode(days, 10),
      recent_failures: recent_failure_summaries(@default_recent_failures),
      tool_stats: Analytics.tool_stats(days),
      score_trend: card_score_trend(slug),
      regressions: Analytics.recent_regressions(days, 10),
      current_yaml: read_card_yaml(slug)
    }
  end

  @doc """
  Call the LLM to produce one improvement proposal. Persists the result
  (or a `malformed` row if the response isn't usable JSON).

  Returns `{:ok, %Proposal{}}` on any persisted row (parse failures
  included), `{:error, reason}` only on infrastructure errors (LLM
  unreachable, card not found, etc.).
  """
  @spec generate_proposal(String.t(), keyword()) ::
          {:ok, Proposal.t()} | {:error, term()}
  def generate_proposal(slug, opts \\ []) when is_binary(slug) do
    ctx = build_context(slug, opts)

    cond do
      ctx.current_yaml in [nil, ""] ->
        {:error, :card_yaml_missing}

      true ->
        case call_llm(ctx) do
          {:ok, raw_text} -> persist_from_raw(slug, ctx, raw_text)
          {:error, _} = err -> err
        end
    end
  end

  # ----- Persist the LLM output (success or malformed) -----

  defp persist_from_raw(slug, _ctx, raw_text) do
    case parse_json(raw_text) do
      {:ok, %{"kind" => "noop"} = decoded} ->
        insert_proposal(%{
          kind: "noop",
          target: slug,
          justification: decoded["justification"] || "",
          status: "rejected",
          decision_reason: "LLM returned noop",
          decided_at: DateTime.utc_now() |> DateTime.truncate(:second),
          decided_by: "improver",
          raw_response: raw_text
        })

      {:ok, decoded} ->
        attrs =
          %{
            kind: decoded["kind"] || "card_edit",
            target: decoded["target"] || slug,
            proposed_body: decoded["proposed_body"],
            justification: decoded["justification"],
            expected_score_delta: parse_float(decoded["expected_score_delta"]),
            supporting_run_ids: list_of_strings(decoded["supporting_run_ids"]),
            status: "pending",
            raw_response: raw_text
          }

        case validate_attrs(attrs) do
          :ok ->
            insert_proposal(attrs)

          {:error, reason} ->
            insert_proposal(
              Map.merge(attrs, %{
                status: "malformed",
                decision_reason: "validation: #{reason}",
                decided_at: DateTime.utc_now() |> DateTime.truncate(:second),
                decided_by: "improver"
              })
            )
        end

      {:error, reason} ->
        insert_proposal(%{
          kind: "card_edit",
          target: slug,
          status: "malformed",
          decision_reason: "json parse: #{inspect(reason) |> String.slice(0, 200)}",
          decided_at: DateTime.utc_now() |> DateTime.truncate(:second),
          decided_by: "improver",
          raw_response: raw_text
        })
    end
  end

  defp insert_proposal(attrs) do
    case %Proposal{} |> Proposal.changeset(attrs) |> Repo.insert() do
      {:ok, p} -> {:ok, p}
      {:error, cs} -> {:error, {:db_error, cs}}
    end
  end

  defp validate_attrs(%{kind: "card_edit", proposed_body: body}) when is_binary(body) and body != "" do
    case YamlElixir.read_from_string(body) do
      {:ok, %{"slug" => _, "name" => _}} -> :ok
      {:ok, _} -> {:error, "missing required keys (slug/name)"}
      {:error, _} -> {:error, "invalid YAML"}
    end
  end

  defp validate_attrs(%{kind: "card_edit"}), do: {:error, "proposed_body is required"}
  defp validate_attrs(_), do: :ok

  # ----- Decisions API -----

  def approve!(%Proposal{} = p, by) when is_binary(by) do
    p
    |> Proposal.changeset(%{
      status: "approved",
      decided_by: by,
      decided_at: DateTime.utc_now() |> DateTime.truncate(:second),
      decision_reason: nil
    })
    |> Repo.update!()
  end

  def reject!(%Proposal{} = p, by, reason) when is_binary(by) do
    p
    |> Proposal.changeset(%{
      status: "rejected",
      decided_by: by,
      decided_at: DateTime.utc_now() |> DateTime.truncate(:second),
      decision_reason: reason
    })
    |> Repo.update!()
  end

  @doc """
  Write the proposal's `proposed_body` to the underlying artifact file.
  Refuses unless the proposal is currently `approved`. Phase 2's
  versioning fires automatically so the change is rollback-safe.
  """
  def apply!(%Proposal{status: "approved"} = p, by) when is_binary(by) do
    case do_apply(p, by) do
      {:ok, _result} ->
        p
        |> Proposal.changeset(%{
          status: "applied",
          applied_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.update!()

      {:error, reason} ->
        p
        |> Proposal.changeset(%{
          status: "failed",
          apply_error: inspect(reason) |> String.slice(0, 500)
        })
        |> Repo.update!()
    end
  end

  # Allow apply on staged_passed (and explicitly on staged_failed if HITL
  # decides to override) to match the Phase 4 flow.
  def apply!(%Proposal{status: status} = p, by)
      when status in ["staged_passed", "staged_failed"] and is_binary(by) do
    case do_apply(p, by) do
      {:ok, _result} ->
        _ = discard_staging!(p, by)

        p
        |> Proposal.changeset(%{
          status: "applied",
          applied_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.update!()

      {:error, reason} ->
        p
        |> Proposal.changeset(%{
          status: "failed",
          apply_error: inspect(reason) |> String.slice(0, 500)
        })
        |> Repo.update!()
    end
  end

  def apply!(%Proposal{} = p, _by),
    do: {:error, {:not_approved, p.status}}

  # ----- Phase 4: staging + auto-validation -----

  @doc """
  Create a temporary staging card with the proposal's body and trigger an
  async eval. Refuses unless the proposal is currently `approved` (HITL
  has reviewed the diff). Sets `status="staging"` plus `staging_slug` and
  `baseline_eval_run_id`. The `Improver.Staging` GenServer watches the
  PubSub topic and finalises the row when the eval completes.

  Returns the updated proposal (now `staging`) on success, or
  `{:error, reason}` if the staging card couldn't be created.
  """
  @spec stage!(Proposal.t(), String.t()) :: Proposal.t() | {:error, term()}
  def stage!(%Proposal{status: "approved", kind: "card_edit"} = p, by) when is_binary(by) do
    staging_slug = "#{p.target}-staging"
    staging_body = rewrite_slug(p.proposed_body, p.target, staging_slug)
    baseline = latest_eval_for(p.target)

    reason = "staging for improvement proposal #{Design.short_sha(p.id)}"

    with {:ok, _} <- Design.save_card_source(staging_slug, staging_body, reason: reason),
         :ok <- Eval.run_card_async(staging_slug) do
      p
      |> Proposal.changeset(%{
        status: "staging",
        staging_slug: staging_slug,
        baseline_eval_run_id: baseline && baseline.id,
        baseline_score: baseline && baseline.average_score,
        decided_by: by,
        decided_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.update!()
    else
      {:error, reason} ->
        # Best-effort cleanup if the file was created but the eval failed.
        _ = remove_staging_card(staging_slug)
        {:error, reason}
    end
  end

  def stage!(%Proposal{} = p, _by), do: {:error, {:not_stageable, p.status}}

  @doc """
  Tear down the staging card (file + DB row). Idempotent — succeeds even if
  the staging slug has already been removed. Does NOT change the proposal's
  status (callers do that explicitly).
  """
  @spec discard_staging!(Proposal.t(), String.t()) :: :ok
  def discard_staging!(%Proposal{staging_slug: nil}, _by), do: :ok

  def discard_staging!(%Proposal{staging_slug: slug}, _by) do
    _ = remove_staging_card(slug)
    :ok
  end

  @doc """
  Called by `Improver.Staging` when an eval finishes on a staging card.
  Computes the delta vs baseline (if any) and updates the proposal's
  status to `staged_passed` (delta >= 0 or no baseline) or
  `staged_failed` (delta < 0).
  """
  @spec record_staging_finish!(Proposal.t(), EvalRun.t()) :: Proposal.t()
  def record_staging_finish!(%Proposal{} = p, %EvalRun{} = eval_run) do
    staging_score = eval_run.average_score || 0.0
    baseline = p.baseline_score
    delta = if baseline, do: staging_score - baseline, else: nil

    next_status =
      cond do
        # No baseline → can't say it's worse; treat as passed so HITL can decide.
        is_nil(baseline) -> "staged_passed"
        delta >= 0 -> "staged_passed"
        true -> "staged_failed"
      end

    p
    |> Proposal.changeset(%{
      status: next_status,
      staging_eval_run_id: eval_run.id,
      staging_score: staging_score,
      score_delta: delta
    })
    |> Repo.update!()
  end

  # Find proposals waiting for staging eval completion on a given slug.
  @doc false
  def list_pending_staging_for_slug(slug) when is_binary(slug) do
    from(p in Proposal, where: p.staging_slug == ^slug and p.status == "staging")
    |> Repo.all()
  end

  # ----- Staging internals -----

  defp latest_eval_for(slug) do
    case Design.get_card_by_slug(slug) do
      nil ->
        nil

      card ->
        from(er in EvalRun,
          where: er.agentic_card_id == ^card.id and er.status == "done",
          order_by: [desc: er.inserted_at],
          limit: 1
        )
        |> Repo.one()
    end
  end

  # Rewrite the YAML body's `slug:` field so the staging card doesn't
  # collide with the original. Defensive: also matches indented entries.
  defp rewrite_slug(body, _from, to) when is_binary(body) do
    Regex.replace(~r/^(\s*slug:\s*)(\S+)/m, body, "\\1#{to}", global: false)
  end

  defp remove_staging_card(slug) do
    case Design.card_source_path(slug) do
      nil -> :ok
      path -> _ = File.rm(path)
    end

    case Design.get_card_by_slug(slug) do
      nil -> :ok
      card -> Repo.delete(card)
    end

    :ok
  rescue
    _ -> :ok
  end

  defp do_apply(%Proposal{kind: "card_edit", target: slug, proposed_body: body} = p, _by)
       when is_binary(body) do
    reason = "improvement proposal #{Design.short_sha(p.id)}"
    Design.save_card_source(slug, body, reason: reason)
  end

  defp do_apply(%Proposal{kind: kind}, _by), do: {:error, {:unsupported_kind, kind}}

  # ----- LLM call -----

  @system_prompt """
  You are an improvement proposer for an Agentic AI Agent. Your job is to
  read the agent's recent failures, tool usage stats, and score trends,
  and propose ONE concrete change to its Agentic Card YAML that should
  reduce failures or raise scores.

  Reply with a SINGLE JSON object — no markdown fences, no prose around it.

  Schema:

      {
        "kind": "card_edit",
        "target": "<existing card slug>",
        "proposed_body": "<the COMPLETE new YAML body for the card>",
        "justification": "<one paragraph citing specific failure modes / tools / scores>",
        "expected_score_delta": <float between -1.0 and 1.0>,
        "supporting_run_ids": ["<run id>", "..."]
      }

  Rules:
  - `proposed_body` must be valid YAML that preserves the required top-level keys:
    slug, name, role, goal, scope, capabilities, tool_policy, reasoning_policy,
    safety_policy, output_contract, evaluation_mapping.
  - Do not remove existing task_taxonomies, capability_matrix, or
    workflow_graphs unless your justification explicitly says why.
  - Be conservative — prefer small, focused changes (one or two fields)
    over a full rewrite.
  - If you cannot identify a clear improvement, reply with
    {"kind": "noop", "justification": "<reason>"}.
  """

  defp call_llm(ctx) do
    messages = [
      %{"role" => "system", "content" => @system_prompt},
      %{"role" => "user", "content" => render_user_message(ctx)}
    ]

    case LLM.Adapter.chat(messages, temperature: 0.2) do
      {:ok, %Response{content: text}} when is_binary(text) and text != "" -> {:ok, text}
      {:ok, _} -> {:error, :empty_llm_response}
      {:error, _} = err -> err
    end
  rescue
    e -> {:error, {:llm_call_exception, Exception.message(e)}}
  end

  defp render_user_message(ctx) do
    """
    == Card slug ==
    #{ctx.slug}

    == Run health (last #{ctx.window_days} days) ==
    #{inspect(ctx.run_health, pretty: true)}

    == Top failure modes ==
    #{inspect(ctx.failures_by_mode, pretty: true)}

    == Tool stats (calls / errors / error_rate / avg ms) ==
    #{inspect(ctx.tool_stats, pretty: true)}

    == Recent eval score trend for this card ==
    #{inspect(ctx.score_trend, pretty: true)}

    == Recent regressions (failed runs) ==
    #{inspect(ctx.regressions, pretty: true)}

    == Current card YAML ==
    ```yaml
    #{ctx.current_yaml}
    ```

    Propose ONE focused change.
    """
  end

  # ----- Internals -----

  defp read_card_yaml(slug) do
    case Design.card_source_path(slug) do
      nil -> nil
      path -> File.read!(path)
    end
  rescue
    _ -> nil
  end

  defp card_score_trend(slug) do
    Analytics.score_trend_per_card(per_card: @default_top_supporting)
    |> Enum.find(&(&1.card_slug == slug))
  end

  defp recent_failure_summaries(limit) do
    Failures.list_recent_occurrences(limit)
    |> Enum.map(fn occ ->
      %{
        id: occ.id,
        run_id: occ.run_id,
        reason: occ.reason,
        mode_id: occ.failure_mode_id,
        at: occ.inserted_at
      }
    end)
  rescue
    _ -> []
  end

  defp parse_json(text) when is_binary(text) do
    # LLMs sometimes wrap JSON in ```json … ``` fences despite instructions.
    cleaned =
      text
      |> String.trim()
      |> strip_fence()

    Jason.decode(cleaned)
  end

  defp strip_fence(text) do
    case Regex.run(~r/^```(?:json)?\s*(.*?)\s*```$/s, text, capture: :all_but_first) do
      [inner] -> inner
      _ -> text
    end
  end

  defp parse_float(nil), do: nil
  defp parse_float(n) when is_number(n), do: n * 1.0

  defp parse_float(str) when is_binary(str) do
    case Float.parse(String.trim(str, "+")) do
      {f, _} -> f
      :error -> nil
    end
  end

  defp parse_float(_), do: nil

  defp list_of_strings(nil), do: []
  defp list_of_strings(list) when is_list(list), do: Enum.map(list, &to_string/1)
  defp list_of_strings(_), do: []
end
