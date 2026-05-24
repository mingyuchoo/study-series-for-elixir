defmodule AgenticAiAgent.Traces do
  @moduledoc """
  Persistence helpers for the trace/observation layer: `runs`, `steps`,
  `tool_calls`. The agent runtime drives these — the schema is shaped
  after the Trace / Observation Schema in `docs/eval.md`.
  """

  import Ecto.Query

  alias AgenticAiAgent.Repo
  alias AgenticAiAgent.Traces.{Approval, Run, Step, ToolCall}

  # ----- Run -----

  def create_run!(attrs) do
    %Run{}
    |> Run.changeset(attrs)
    |> Repo.insert!()
  end

  def update_run!(%Run{} = run, attrs) do
    run
    |> Run.changeset(attrs)
    |> Repo.update!()
  end

  def get_run!(id), do: Repo.get!(Run, id)

  def list_recent_runs(limit \\ 25) do
    Run
    |> order_by([r], desc: r.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Hard-delete a single run. Children are pruned by FK cascade
  (`steps`, `tool_calls`, `approvals`, `failure_occurrences`).
  References that should outlive the trace are nilified
  (`eval_cases.run_id`, child `runs.parent_run_id`).
  """
  @spec delete_run!(Run.t() | binary()) :: Run.t()
  def delete_run!(%Run{} = run), do: Repo.delete!(run)
  def delete_run!(id) when is_binary(id), do: id |> get_run!() |> Repo.delete!()

  @doc """
  Hard-delete every run whose `inserted_at` is strictly older than
  `days_ago` days from now (UTC). Returns the number of rows deleted.
  Children cascade as in `delete_run!/1`.

  `days_ago` must be a positive integer — refuses 0 / negative values
  so a misclick never wipes the whole table.
  """
  @spec delete_runs_older_than(pos_integer()) :: non_neg_integer()
  def delete_runs_older_than(days_ago) when is_integer(days_ago) and days_ago > 0 do
    cutoff = DateTime.utc_now() |> DateTime.add(-days_ago * 86_400, :second)

    {n, _} =
      Run
      |> where([r], r.inserted_at < ^cutoff)
      |> Repo.delete_all()

    n
  end

  def delete_runs_older_than(_), do: 0

  # ----- Steps -----

  def add_step!(%Run{id: run_id}, kind, payload, latency_ms \\ nil, extra \\ %{}) do
    base = %{
      run_id: run_id,
      idx: next_step_idx(run_id),
      kind: to_string(kind),
      payload: payload,
      latency_ms: latency_ms
    }

    %Step{}
    |> Step.changeset(Map.merge(base, extra))
    |> Repo.insert!()
  end

  @doc """
  Accumulate per-step token cost onto a run row. Skips silently when any
  argument is nil so the caller doesn't need to branch.
  """
  def accumulate_cost!(%Run{} = run, micro_usd, prompt_tokens, completion_tokens)
      when is_integer(micro_usd) do
    cs = %{
      cost_micro_usd: (run.cost_micro_usd || 0) + micro_usd,
      prompt_tokens: (run.prompt_tokens || 0) + (prompt_tokens || 0),
      completion_tokens: (run.completion_tokens || 0) + (completion_tokens || 0)
    }

    run
    |> Run.changeset(cs)
    |> Repo.update!()
  end

  def accumulate_cost!(run, _, _, _), do: run

  defp next_step_idx(run_id) do
    Repo.one(
      from s in Step,
        where: s.run_id == ^run_id,
        select: coalesce(max(s.idx), -1)
    ) + 1
  end

  def list_steps(run_id) do
    Step
    |> where([s], s.run_id == ^run_id)
    |> order_by([s], asc: s.idx)
    |> Repo.all()
  end

  # ----- Tool calls -----

  def add_tool_call!(%Run{id: run_id}, step, attrs) do
    base = %{run_id: run_id, step_id: step && step.id}

    %ToolCall{}
    |> ToolCall.changeset(Map.merge(base, attrs))
    |> Repo.insert!()
  end

  def list_tool_calls(run_id) do
    ToolCall
    |> where([t], t.run_id == ^run_id)
    |> order_by([t], asc: t.inserted_at)
    |> Repo.all()
  end

  # ----- Approvals (HITL) -----

  def create_approval!(attrs) do
    %Approval{}
    |> Approval.changeset(attrs)
    |> Repo.insert!()
  end

  def update_approval!(%Approval{} = approval, attrs) do
    approval
    |> Approval.changeset(attrs)
    |> Repo.update!()
  end

  def get_approval!(id), do: Repo.get!(Approval, id)

  def get_approval(id), do: Repo.get(Approval, id)

  def list_approvals(run_id) do
    Approval
    |> where([a], a.run_id == ^run_id)
    |> order_by([a], asc: a.inserted_at)
    |> Repo.all()
  end

  def list_pending_approvals do
    Approval
    |> where([a], a.status == "pending")
    |> order_by([a], asc: a.inserted_at)
    |> Repo.all()
  end

  # ----- Sub-runs -----

  def list_child_runs(run_id) do
    Run
    |> where([r], r.parent_run_id == ^run_id)
    |> order_by([r], asc: r.inserted_at)
    |> Repo.all()
  end
end
