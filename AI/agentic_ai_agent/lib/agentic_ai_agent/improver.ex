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

  alias AgenticAiAgent.{Analytics, Design, Eval, Failures, LLM, Repo, Safety, Skills}
  alias AgenticAiAgent.Agent.{Diagnostics, ReflexionInsights}
  alias AgenticAiAgent.Eval.EvalRun
  alias AgenticAiAgent.Improver.{Patterns, Proposal}
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
  def find_previous_card_version(%Proposal{
        kind: "card_edit",
        target: slug,
        applied_at: applied_at
      })
      when not is_nil(applied_at) do
    AgenticAiAgent.Design.list_card_versions(slug)
    |> Enum.find(fn v -> DateTime.compare(v.inserted_at, applied_at) == :lt end)
  end

  def find_previous_card_version(_), do: nil

  @doc """
  Operator-triggered rollback of an applied proposal. Mirrors the
  Scheduler's autonomous rollback path but synchronous: locates the
  previous `CardVersion`, restores it, marks the proposal rolled back,
  and runs the post-rollback safety re-audit (`Improver.Scheduler`
  emits a notification if the rollback re-introduces a violation).

  Refuses unless the proposal is `applied` and not already rolled back.

  Returns:
    * `{:ok, updated_proposal}` — restore + mark succeeded
    * `{:error, :already_rolled_back}` — idempotent guard
    * `{:error, :not_applied}` — proposal must be in `applied` status
    * `{:error, :no_previous_version}` — nothing to roll back to
    * `{:error, reason}` — restore_card_version failed
  """
  @spec rollback!(Proposal.t(), String.t()) ::
          {:ok, Proposal.t()} | {:error, term()}
  def rollback!(%Proposal{rolled_back_at: ts}, _by) when not is_nil(ts),
    do: {:error, :already_rolled_back}

  def rollback!(%Proposal{status: status} = _p, _by) when status != "applied",
    do: {:error, :not_applied}

  def rollback!(%Proposal{} = p, by) when is_binary(by) do
    case find_previous_card_version(p) do
      nil ->
        _ =
          AgenticAiAgent.Improver.SchedulerDecisions.record("no_previous_version",
            dry_run: false,
            card_slug: p.target,
            proposal_id: p.id,
            detail: "operator rollback requested but no version row predates applied_at"
          )

        {:error, :no_previous_version}

      version ->
        pre_rollback_yaml = read_card_yaml(p.target)
        reason = "operator rollback by #{by}"

        case Design.restore_card_version(version, reason: reason) do
          {:ok, _} ->
            updated = mark_rolled_back!(p, reason)

            _ =
              AgenticAiAgent.Improver.SchedulerDecisions.record("rolled_back",
                dry_run: false,
                card_slug: p.target,
                proposal_id: p.id,
                detail: reason,
                metadata: %{"by" => by}
              )

            # Best-effort safety re-audit. Emits its own notification +
            # decision row when the restored YAML re-introduces a
            # high-severity violation.
            _ =
              AgenticAiAgent.Improver.Scheduler.audit_rollback_safety(
                updated,
                pre_rollback_yaml,
                read_card_yaml(p.target)
              )

            {:ok, updated}

          {:error, restore_err} ->
            _ =
              AgenticAiAgent.Improver.SchedulerDecisions.record("restore_failed",
                dry_run: false,
                card_slug: p.target,
                proposal_id: p.id,
                detail: inspect(restore_err) |> String.slice(0, 200)
              )

            {:error, restore_err}
        end
    end
  end

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
    diagnose? = Keyword.get(opts, :diagnose, true)

    %{
      slug: slug,
      window_days: days,
      run_health: Analytics.run_health(days),
      failures_by_mode: Analytics.failures_by_mode(days, 10),
      recent_failures: recent_failure_summaries(@default_recent_failures),
      tool_stats: Analytics.tool_stats(days),
      skill_stats: Analytics.skill_stats(days),
      failures_by_skill: Analytics.failures_by_skill(days),
      score_trend: card_score_trend(slug),
      regressions: Analytics.recent_regressions(days, 10),
      current_yaml: read_card_yaml(slug),
      existing_skills: list_skill_summaries(),
      root_cause: if(diagnose?, do: maybe_diagnose(slug, opts), else: nil),
      recurring_critiques: ReflexionInsights.recurring_themes_for_card(slug, days: days),
      transferable_patterns: Patterns.recent_successful(slug, days: days)
    }
  end

  # Best-effort root-cause pass. Diagnostics is advisory — if it fails
  # or finds no signal, the Improver still produces a proposal using
  # statistics alone.
  defp maybe_diagnose(slug, opts) do
    case Diagnostics.diagnose_card(slug, opts) do
      {:ok, diag} -> diag
      {:skipped, _} -> nil
      {:error, _} -> nil
    end
  rescue
    _ -> nil
  end

  defp list_skill_summaries do
    for s <- Skills.list() do
      %{slug: s.slug, name: s.name, description: s.description}
    end
  rescue
    _ -> []
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

  defp persist_from_raw(slug, ctx, raw_text) do
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
            proposed_change: decoded["proposed_change"],
            justification: decoded["justification"],
            expected_score_delta: parse_float(decoded["expected_score_delta"]),
            supporting_run_ids: list_of_strings(decoded["supporting_run_ids"]),
            inspired_by_proposal_id: Patterns.validate_inspired_by(decoded["inspired_by"]),
            status: "pending",
            raw_response: raw_text
          }
          |> add_safety_audit(ctx.current_yaml)
          |> add_root_cause(ctx.root_cause)
          |> add_pattern_tag()

        case validate_attrs(attrs) do
          :ok ->
            with {:ok, proposal} <- insert_proposal(attrs) do
              _ = link_recurring_insights(proposal, ctx)
              {:ok, proposal}
            end

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

  # Run static safety audit on card_edit proposals. Stores both the
  # detailed audit map and the top-level verdict on the row so the UI /
  # Scheduler can filter cheaply.
  defp add_safety_audit(%{kind: "card_edit", proposed_body: body} = attrs, current_yaml)
       when is_binary(body) do
    {:ok, audit} = Safety.audit_card(current_yaml, body)

    attrs
    |> Map.put(:safety_audit, jsonable(audit))
    |> Map.put(:safety_verdict, Atom.to_string(audit.verdict))
  rescue
    _ -> attrs
  end

  # Synthesize the post-change YAML for a tool_policy_change and run
  # the same audit. This catches a deny-list-shrink or a high-risk-tool
  # addition before the proposal is offered for approval — even though
  # the body is a small patch instead of a full YAML.
  defp add_safety_audit(
         %{kind: "tool_policy_change", proposed_change: change} = attrs,
         current_yaml
       )
       when is_binary(current_yaml) and is_map(change) do
    case apply_tool_policy_change(current_yaml, change) do
      {:ok, synthesized_yaml} ->
        {:ok, audit} = Safety.audit_card(current_yaml, synthesized_yaml)

        attrs
        |> Map.put(:safety_audit, jsonable(audit))
        |> Map.put(:safety_verdict, Atom.to_string(audit.verdict))

      {:error, _} ->
        attrs
    end
  rescue
    _ -> attrs
  end

  defp add_safety_audit(attrs, _), do: attrs

  # Persist the diagnosis alongside the proposal so the UI and downstream
  # auto-rollback logic can trace WHY a proposal was made, not just what
  # it changes. A nil diagnosis means no failed runs were available in
  # the window — the proposal stands on aggregate analytics alone.
  defp add_root_cause(attrs, nil), do: attrs

  defp add_root_cause(attrs, %{} = diag) do
    narrative =
      [
        Map.get(diag, :summary),
        Map.get(diag, :narrative),
        "recurring_pattern: #{Map.get(diag, :recurring_pattern, "")}",
        "suggested_fix_kind: #{Map.get(diag, :suggested_fix_kind, "")} " <>
          "(confidence #{Map.get(diag, :confidence, 0.0)})"
      ]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join("\n\n")

    attrs
    |> Map.put(:root_cause, narrative)
    |> Map.put(:root_cause_summary, Map.get(diag, :summary))
    |> Map.put(:root_cause_run_ids, Map.get(diag, :run_ids, []))
  end

  # Classify the new proposal so future build_context calls can surface
  # it as a transferable pattern. Tag derives from kind + justification
  # + root_cause_summary; see `Improver.Patterns.extract_pattern_tag/1`.
  defp add_pattern_tag(attrs) do
    Map.put(attrs, :pattern_tag, Patterns.extract_pattern_tag(attrs))
  rescue
    _ -> attrs
  end

  # SQLite's :map column needs string-keyed JSON-safe values. Atoms in
  # the audit (e.g. verdict) must be coerced.
  defp jsonable(audit) do
    %{
      "score" => audit.score,
      "verdict" => Atom.to_string(audit.verdict),
      "violations" => audit.violations,
      "warnings" => audit.warnings
    }
  end

  defp insert_proposal(attrs) do
    case %Proposal{} |> Proposal.changeset(attrs) |> Repo.insert() do
      {:ok, p} -> {:ok, p}
      {:error, cs} -> {:error, {:db_error, cs}}
    end
  end

  defp validate_attrs(%{kind: "card_edit", proposed_body: body})
       when is_binary(body) and body != "" do
    case YamlElixir.read_from_string(body) do
      {:ok, %{"slug" => _, "name" => _}} -> :ok
      {:ok, _} -> {:error, "missing required keys (slug/name)"}
      {:error, _} -> {:error, "invalid YAML"}
    end
  end

  defp validate_attrs(%{kind: "card_edit"}), do: {:error, "proposed_body is required"}

  defp validate_attrs(%{kind: "skill_add", target: slug, proposed_body: body})
       when is_binary(body) and body != "" and is_binary(slug) and slug != "" do
    cond do
      not Regex.match?(~r/\A[a-z0-9][a-z0-9_]*\z/, slug) ->
        {:error, "skill slug must be lowercase letters/digits/underscores"}

      true ->
        validate_skill_body(body)
    end
  end

  defp validate_attrs(%{kind: "skill_add"}),
    do: {:error, "skill_add requires both target (slug) and proposed_body"}

  defp validate_attrs(%{kind: "tool_policy_change", target: slug, proposed_change: change})
       when is_binary(slug) and slug != "" and is_map(change) do
    allow = Map.get(change, "allow") || Map.get(change, :allow)
    deny = Map.get(change, "deny") || Map.get(change, :deny)

    cond do
      is_nil(allow) and is_nil(deny) ->
        {:error, "tool_policy_change requires at least one of allow/deny in proposed_change"}

      not is_nil(allow) and not all_strings?(allow) ->
        {:error, "tool_policy_change.allow must be a list of strings"}

      not is_nil(deny) and not all_strings?(deny) ->
        {:error, "tool_policy_change.deny must be a list of strings"}

      true ->
        :ok
    end
  end

  defp validate_attrs(%{kind: "tool_policy_change"}),
    do: {:error, "tool_policy_change requires target (card slug) and proposed_change map"}

  defp validate_attrs(_), do: :ok

  defp all_strings?(list) when is_list(list),
    do: Enum.all?(list, &is_binary/1)

  defp all_strings?(_), do: false

  # A valid SKILL.md starts with a YAML frontmatter block delimited by `---`
  # and contains at least `name` and `description` in that frontmatter.
  defp validate_skill_body(body) do
    case String.split(body, ~r/^---\s*\n/m, parts: 3) do
      ["", frontmatter, _rest] ->
        case YamlElixir.read_from_string(frontmatter) do
          {:ok, %{"name" => _, "description" => _}} -> :ok
          {:ok, _} -> {:error, "skill frontmatter missing name/description"}
          {:error, _} -> {:error, "skill frontmatter is not valid YAML"}
        end

      _ ->
        {:error, "skill body must start with a `---`-delimited YAML frontmatter"}
    end
  end

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
    baseline_perf = baseline && Analytics.eval_run_perf(baseline.id)

    reason = "staging for improvement proposal #{Design.short_sha(p.id)}"

    with {:ok, _} <- Design.save_card_source(staging_slug, staging_body, reason: reason),
         :ok <- Eval.run_card_async(staging_slug) do
      p
      |> Proposal.changeset(%{
        status: "staging",
        staging_slug: staging_slug,
        baseline_eval_run_id: baseline && baseline.id,
        baseline_score: baseline && baseline.average_score,
        baseline_cost_micro_usd: round_or_nil(baseline_perf && baseline_perf.avg_cost_micro_usd),
        baseline_latency_ms: round_or_nil(baseline_perf && baseline_perf.avg_latency_ms),
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

  # Other kinds (skill_add) bypass staging — skills don't have an eval path
  # of their own yet. Operator applies directly from the approved state.
  def stage!(%Proposal{kind: kind}, _by) when kind != "card_edit",
    do: {:error, {:not_stageable_kind, kind}}

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
    staging_perf = Analytics.eval_run_perf(eval_run.id)

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
      score_delta: delta,
      staging_cost_micro_usd: round_or_nil(staging_perf.avg_cost_micro_usd),
      staging_latency_ms: round_or_nil(staging_perf.avg_latency_ms)
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

  defp do_apply(%Proposal{kind: "skill_add", target: slug, proposed_body: body} = p, _by)
       when is_binary(body) do
    reason = "improvement proposal #{Design.short_sha(p.id)}"
    Skills.save_source(slug, body, reason: reason)
  end

  defp do_apply(
         %Proposal{kind: "tool_policy_change", target: slug, proposed_change: change} = p,
         _by
       )
       when is_binary(slug) and is_map(change) do
    reason = "improvement proposal #{Design.short_sha(p.id)} (tool_policy_change)"

    with current_yaml when is_binary(current_yaml) <- read_card_yaml(slug),
         {:ok, new_body} <- apply_tool_policy_change(current_yaml, change) do
      Design.save_card_source(slug, new_body, reason: reason)
    else
      nil -> {:error, :card_yaml_missing}
      {:error, _} = err -> err
    end
  end

  defp do_apply(%Proposal{kind: kind}, _by), do: {:error, {:unsupported_kind, kind}}

  @doc """
  Replace ONLY the `tool_policy:` block in a card YAML body. All other
  top-level blocks (multi-line role/goal strings, deeply nested
  workflow_graphs, etc.) are preserved byte-for-byte. The merged
  tool_policy is emitted in inline-list style — matching the seeded
  cards and round-tripping cleanly through `YamlElixir`.

  Only keys present in `change` are overwritten — pass `"allow": []`
  to clear the allow list explicitly. Other subkeys of tool_policy
  (max_tool_calls_per_run, parallel_tool_calls, ...) are preserved from
  the parsed base.

  Returns `{:ok, new_yaml}` or `{:error, reason}`.
  """
  @spec apply_tool_policy_change(String.t(), map()) :: {:ok, String.t()} | {:error, term()}
  def apply_tool_policy_change(current_yaml, change)
      when is_binary(current_yaml) and is_map(change) do
    with {:ok, %{} = parsed} <- safe_parse_yaml(current_yaml) do
      base = Map.get(parsed, "tool_policy") || %{}
      merged = base |> maybe_set(change, "allow") |> maybe_set(change, "deny")
      serialized = serialize_tool_policy_block(merged)

      new_yaml =
        case replace_top_block(current_yaml, "tool_policy", serialized) do
          {:ok, replaced} -> replaced
          :not_found -> String.trim_trailing(current_yaml) <> "\n\n" <> serialized
        end

      {:ok, new_yaml}
    else
      {:error, _} = err -> err
    end
  end

  defp safe_parse_yaml(yaml) do
    case YamlElixir.read_from_string(yaml) do
      {:ok, %{} = m} -> {:ok, m}
      {:ok, _} -> {:error, :card_yaml_not_map}
      {:error, reason} -> {:error, {:yaml_parse, reason}}
    end
  end

  defp maybe_set(map, change, key) do
    case Map.get(change, key, Map.get(change, String.to_atom(key))) do
      nil -> map
      value -> Map.put(map, key, value)
    end
  end

  # Render a tool_policy sub-map. Inline lists for allow/deny (compact
  # diffs), simple scalars for the rest. Sub-keys not in `policy` are
  # omitted.
  defp serialize_tool_policy_block(policy) when is_map(policy) do
    # Preserve a stable key order so version diffs stay readable.
    order = ~w(allow deny max_tool_calls_per_run parallel_tool_calls)
    extras = Map.keys(policy) -- order
    keys = (order ++ extras) |> Enum.filter(&Map.has_key?(policy, &1))

    "tool_policy:\n" <>
      Enum.map_join(keys, "\n", fn k ->
        "  #{k}: #{render_tp_value(policy[k])}"
      end)
  end

  defp render_tp_value(v) when is_list(v), do: "[" <> Enum.map_join(v, ", ", &to_string/1) <> "]"
  defp render_tp_value(v) when is_boolean(v) or is_number(v), do: to_string(v)
  defp render_tp_value(v) when is_binary(v), do: v
  defp render_tp_value(v), do: inspect(v)

  # Replace the YAML block that starts at `^key:` and runs until the
  # next top-level key (matching `^[a-z_]+:` at column 0) or EOF. The
  # blank lines between blocks are preserved on either side of the
  # replacement.
  @spec replace_top_block(String.t(), String.t(), String.t()) ::
          {:ok, String.t()} | :not_found
  defp replace_top_block(text, key, new_block) when is_binary(text) and is_binary(key) do
    # (?m) for multiline anchors. The block is "key: ... up to the next
    # top-level line OR end of string". `(?=^[a-z_]+:|\z)` is a
    # lookahead that doesn't consume.
    regex = ~r/(?m)^#{Regex.escape(key)}:.*?(?=^[a-zA-Z_][a-zA-Z0-9_]*:|\z)/s

    if Regex.match?(regex, text) do
      replaced = Regex.replace(regex, text, new_block <> "\n", global: false)
      {:ok, replaced}
    else
      :not_found
    end
  end

  # ----- LLM call -----

  @system_prompt """
  You are an improvement proposer for an Agentic AI Agent. Your job is to
  read the agent's recent failures, tool usage stats, and score trends,
  and propose ONE concrete change that should reduce failures or raise scores.

  Reply with a SINGLE JSON object — no markdown fences, no prose around it.

  You may choose between three kinds of change:

  (A) `card_edit` — modify the YAML of an existing agentic card:

      {
        "kind": "card_edit",
        "target": "<existing card slug>",
        "proposed_body": "<the COMPLETE new YAML body for the card>",
        "justification": "<one paragraph citing specific failure modes / tools / scores>",
        "expected_score_delta": <float between -1.0 and 1.0>,
        "supporting_run_ids": ["<run id>", "..."]
      }

  Rules for `card_edit`:
  - `proposed_body` must be valid YAML preserving the required top-level keys:
    slug, name, role, goal, scope, capabilities, tool_policy, reasoning_policy,
    safety_policy, output_contract, evaluation_mapping.
  - Do not remove existing task_taxonomies, capability_matrix, or
    workflow_graphs unless your justification explicitly says why.
  - Be conservative — prefer small, focused changes (one or two fields)
    over a full rewrite.

  (B) `skill_add` — author a new SKILL.md or revise an existing one:

      {
        "kind": "skill_add",
        "target": "<skill slug>",
        "proposed_body": "<the COMPLETE SKILL.md text>",
        "justification": "<one paragraph: what task pattern this skill encodes and why it helps>",
        "expected_score_delta": <float>,
        "supporting_run_ids": ["<run id>", "..."]
      }

  Rules for `skill_add`:
  - The skill slug must be lowercase + underscore (e.g. `web_research`).
  - `proposed_body` MUST start with a YAML frontmatter block delimited by `---`,
    containing at least `name` and `description`. Followed by the procedural body.
  - Example frontmatter:
        ---
        name: web_research
        description: Multi-source web research with citation.
        tools_used: [web_search, http_fetch]
        ---
  - Only propose a new skill when there is a clear recurring task pattern in
    the failure / tool data that an existing skill does not already cover.
  - To revise an existing skill, set `target` to its slug and supply the full
    new body. Phase 2 versioning will snapshot the previous body automatically.

  (C) `tool_policy_change` — narrow change to one card's `tool_policy.allow`
  or `tool_policy.deny`:

      {
        "kind": "tool_policy_change",
        "target": "<existing card slug>",
        "proposed_change": {
          "allow": ["<full new allow list>"],
          "deny":  ["<full new deny list>"]
        },
        "justification": "<one paragraph: which failures or risks does this address?>",
        "expected_score_delta": <float>,
        "supporting_run_ids": ["<run id>", "..."]
      }

  Rules for `tool_policy_change`:
  - At least one of `allow` / `deny` must be present.
  - Each value is the COMPLETE replacement list (not a diff). Include
    every tool you want to keep.
  - Choose this kind over `card_edit` whenever the change is purely a
    tool gating decision — the patch is smaller, easier for an operator
    to review, and runs through the same safety audit as a card edit.
  - Removing a tool from `deny` or adding a known-risky tool to `allow`
    will fail the safety audit and require human approval.

  Selection guidance:
  - Use `card_edit` for prompt / role / reasoning_policy / output_contract changes.
  - Use `skill_add` when a recurring task pattern needs its own procedure.
  - Use `tool_policy_change` for surgical changes to tool gating ONLY.

  Cross-card learning:
  - You will be shown a list of `transferable_patterns` — applied
    proposals from OTHER cards that lifted their eval score. When one
    of these clearly applies to the current card's failure profile,
    set `"inspired_by": "<that proposal's id>"` in your response so
    the linkage is recorded. Only cite an id that actually appears in
    the transferable_patterns list.
  - When inspired, MIMIC the kind + pattern_tag of the source. Don't
    invent a new change shape if a proven one fits.

  If you cannot identify a clear improvement, reply with
  `{"kind": "noop", "justification": "<reason>"}`.
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

    == Skill (sub-agent) stats: per-skill total / success_rate / failed / avg_latency ==
    Use this to spot a SKILL that's underperforming — e.g. "web_research has
    60% success" suggests a `skill_add` revision targeting that slug.
    #{inspect(ctx.skill_stats, pretty: true)}

    == Failures attributed to specific skills (failure_mode breakdown per skill) ==
    #{inspect(ctx.failures_by_skill, pretty: true)}

    == Recent eval score trend for this card ==
    #{inspect(ctx.score_trend, pretty: true)}

    == Recent regressions (failed runs) ==
    #{inspect(ctx.regressions, pretty: true)}

    == Existing skills (do NOT duplicate; revise an existing one if relevant) ==
    #{inspect(ctx.existing_skills, pretty: true)}

    == Root-cause diagnosis of recent failed runs ==
    #{render_root_cause(ctx.root_cause)}

    == Recurring self-critique themes (the agent's own reflexion) ==
    These themes are the SAME weakness flagged by the self-critic across
    multiple recent runs. A proposal that targets one of them carries
    extra weight: it addresses something the agent is already aware of.
    #{render_recurring_critiques(ctx.recurring_critiques)}

    == Transferable patterns (what worked on OTHER cards) ==
    Each entry is an applied proposal that lifted its target's eval
    score. Consider whether the same pattern fits this card; if so, set
    `inspired_by` to the listed id.
    #{render_transferable_patterns(ctx.transferable_patterns)}

    == Current card YAML ==
    ```yaml
    #{ctx.current_yaml}
    ```

    Propose ONE focused change (kind A `card_edit`, B `skill_add`, or
    C `tool_policy_change`).
    Where a root-cause diagnosis is provided, your justification SHOULD
    reference it explicitly and the proposed change SHOULD target the
    specific step/tool/clause it names.
    """
  end

  defp render_root_cause(nil), do: "(no diagnosis available — no failed runs in the window)"

  defp render_root_cause(%{
         summary: summary,
         narrative: narrative,
         recurring_pattern: pattern,
         suggested_fix_kind: kind,
         confidence: confidence,
         run_ids: run_ids
       }) do
    """
    summary: #{summary}
    recurring_pattern: #{pattern}
    suggested_fix_kind: #{kind} (confidence #{Float.round(confidence, 2)})
    derived from runs: #{Enum.join(run_ids, ", ")}

    narrative:
    #{narrative}
    """
  end

  defp render_root_cause(_), do: "(no diagnosis available)"

  defp render_recurring_critiques([]),
    do: "(no recurring critiques crossed the saturation threshold)"

  defp render_recurring_critiques(list) when is_list(list) do
    list
    |> Enum.map_join("\n\n", fn t ->
      """
      - theme: #{t.theme} (×#{t.count})
        sample: #{t.sample_critique}
      """
    end)
  end

  defp render_transferable_patterns([]),
    do: "(no successful proposals on other cards in the window)"

  defp render_transferable_patterns(list) when is_list(list) do
    list
    |> Enum.map_join("\n\n", fn p ->
      tag = p.pattern_tag || "untagged"
      delta = (p.score_delta && Float.round(p.score_delta, 3)) || "?"
      just = (p.justification || "") |> String.slice(0, 240)

      """
      - id: #{p.id}
        from_card: #{p.target}
        kind: #{p.kind}
        pattern_tag: #{tag}
        score_delta: +#{delta}
        justification: #{just}
      """
    end)
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

  # Used to coerce float averages from Analytics into integer columns on
  # the Proposal row. Nil-safe so callers can pipe through without
  # branching.
  defp round_or_nil(nil), do: nil
  defp round_or_nil(n) when is_number(n), do: round(n)

  # Best-effort: attribute every recurring reflexion theme on the card
  # to this proposal so the operator can audit where the proposal came
  # from. Silent on errors — linkage is metadata, never load-bearing.
  defp link_recurring_insights(%Proposal{id: id, target: slug}, %{
         recurring_critiques: themes
       })
       when is_list(themes) and themes != [] do
    theme_keys = Enum.map(themes, & &1.theme) |> Enum.reject(&is_nil/1)
    _ = ReflexionInsights.link_proposal!(slug, theme_keys, id)
    :ok
  rescue
    _ -> :ok
  end

  defp link_recurring_insights(_, _), do: :ok
end
