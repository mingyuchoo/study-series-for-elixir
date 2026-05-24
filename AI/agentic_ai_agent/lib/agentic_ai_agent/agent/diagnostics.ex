defmodule AgenticAiAgent.Agent.Diagnostics do
  @moduledoc """
  Root-cause analysis for failed (or low-scoring) runs.

  The `Improver` already sees failures as *statistics* — counts per
  failure mode, top tool error rates, score regressions. What it does
  NOT see is the actual decision chain: "step 3 of card X called
  `python_exec` with empty input because the planner skipped the
  retrieve step." Without that chain, proposals become generic
  ("tighten the system prompt") instead of targeted ("require a
  `retrieve` step before any `python_exec`").

  This module closes that gap. Given one or more failed runs, it loads
  the full step / tool-call trajectory, asks the LLM to identify the
  causal chain, and returns a structured diagnosis. The result is
  consumed by `AgenticAiAgent.Improver` and stored on the
  `improvement_proposals` row (`root_cause`, `root_cause_summary`,
  `root_cause_run_ids`).

  ## Lifecycle

      candidate_run_ids/2     → pick recent failed/low-score runs for a card
      load_trajectory/1       → run + steps + tool_calls + failure_occurrences
      summarize_trajectory/1  → compact text suitable for an LLM prompt
      diagnose/1              → call the LLM, parse the JSON, return the diagnosis
      diagnose_card/2         → orchestrate the full pipeline for one card slug

  The LLM call is intentionally cheap: low temperature, capped token
  budget, and at most a handful of recent failed runs. Diagnostics is
  advisory — if the LLM is unreachable or returns garbage the caller
  receives `{:error, reason}` and continues without a root cause.
  """

  import Ecto.Query

  alias AgenticAiAgent.{LLM, Repo}
  alias AgenticAiAgent.Design.AgenticCard
  alias AgenticAiAgent.Failures.FailureOccurrence
  alias AgenticAiAgent.LLM.Response
  alias AgenticAiAgent.Traces.{Run, Step, ToolCall}

  require Logger

  @default_max_runs 5
  @default_max_steps_per_run 30
  @default_max_completion_tokens 600
  @max_payload_chars 240

  @system_prompt """
  You are a root-cause analyst for an autonomous AI agent. You will be
  given one or more FAILED or LOW-SCORING runs of the same agentic
  card. Each run is presented as an ordered list of steps (plan, act,
  observe, tool_call, reflect, final) and any failure occurrences that
  were recorded.

  Your job is to identify the SHARED causal chain — what specific
  decision, missing step, prompt ambiguity, tool misuse, or bad input
  caused these runs to fail.

  Reply with a SINGLE JSON object — no markdown fences, no extra prose:

      {
        "summary": "<≤120 chars one-line headline of the root cause>",
        "narrative": "<2–4 sentences naming the exact step / tool / prompt clause that broke>",
        "recurring_pattern": "<one sentence: what trait do these failures share?>",
        "suggested_fix_kind": "card_edit" | "skill_add" | "tool_policy_change" | "unknown",
        "confidence": <float 0.0–1.0>
      }

  Rules:
  - Be specific. "The planner made a mistake" is useless. "Step 3 called
    `web_search` with an empty query because the planner used the user's
    raw message instead of extracting a search term" is useful.
  - If the runs do NOT share a common cause, set summary to
    "no common cause" and confidence below 0.3.
  - Never invent steps that aren't in the trajectory.
  - Be terse. The narrative drives a focused improvement proposal, not a
    post-mortem.
  """

  @typedoc "Structured diagnosis returned to the Improver."
  @type diagnosis :: %{
          summary: String.t(),
          narrative: String.t(),
          recurring_pattern: String.t(),
          suggested_fix_kind: String.t(),
          confidence: float(),
          run_ids: [String.t()]
        }

  # ----- Public API -----

  @doc """
  Full pipeline for one card slug: pick candidate runs, load their
  trajectories, ask the LLM for a root-cause analysis. Returns the
  diagnosis or `{:skipped, reason}` when there isn't enough signal to
  diagnose (e.g. no failed runs in the window).

  Options:
    * `:max_runs` — how many failed runs to analyse together (default 5)
    * `:days` — lookback window for picking candidates (default 14)
    * `:adapter` — override the LLM adapter
  """
  @spec diagnose_card(String.t(), keyword()) ::
          {:ok, diagnosis()} | {:skipped, atom()} | {:error, term()}
  def diagnose_card(slug, opts \\ []) when is_binary(slug) do
    max_runs = Keyword.get(opts, :max_runs, @default_max_runs)
    days = Keyword.get(opts, :days, 14)

    case candidate_run_ids(slug, max_runs: max_runs, days: days) do
      [] ->
        {:skipped, :no_failed_runs}

      run_ids ->
        trajectories =
          run_ids
          |> Enum.map(&load_trajectory/1)
          |> Enum.reject(&is_nil/1)

        case trajectories do
          [] ->
            {:skipped, :no_trajectories}

          trs ->
            diagnose(trs, opts)
        end
    end
  end

  @doc """
  Pick recent failed (status="failed") or eval-flagged runs for a card
  slug. Newest first. Returns an empty list when nothing matches —
  callers should treat that as "no diagnostic signal available."
  """
  @spec candidate_run_ids(String.t(), keyword()) :: [String.t()]
  def candidate_run_ids(slug, opts \\ []) when is_binary(slug) do
    max_runs = Keyword.get(opts, :max_runs, @default_max_runs)
    days = Keyword.get(opts, :days, 14)
    cutoff = DateTime.utc_now() |> DateTime.add(-days * 86_400, :second)

    card_id =
      case Repo.get_by(AgenticCard, slug: slug) do
        nil -> nil
        %AgenticCard{id: id} -> id
      end

    base_query =
      from r in Run,
        where: r.status == "failed" and r.inserted_at >= ^cutoff,
        order_by: [desc: r.inserted_at],
        limit: ^max_runs,
        select: r.id

    base_query =
      if card_id, do: where(base_query, [r], r.agentic_card_id == ^card_id), else: base_query

    Repo.all(base_query)
  rescue
    _ -> []
  end

  @doc """
  Load a single run's full trajectory (run row + ordered steps + tool
  calls + failure occurrences). Returns `nil` when the run doesn't
  exist. Errors from preload are swallowed — the diagnostic step must
  never crash the caller.
  """
  @spec load_trajectory(String.t()) :: map() | nil
  def load_trajectory(run_id) when is_binary(run_id) do
    case Repo.get(Run, run_id) do
      nil ->
        nil

      %Run{} = run ->
        steps =
          from(s in Step, where: s.run_id == ^run_id, order_by: [asc: s.idx])
          |> Repo.all()

        tool_calls =
          from(t in ToolCall, where: t.run_id == ^run_id, order_by: [asc: t.inserted_at])
          |> Repo.all()

        failures =
          from(o in FailureOccurrence,
            where: o.run_id == ^run_id,
            order_by: [asc: o.inserted_at]
          )
          |> Repo.all()
          |> Repo.preload(:failure_mode)

        %{
          run: run,
          steps: steps,
          tool_calls: tool_calls,
          failures: failures
        }
    end
  rescue
    _ -> nil
  end

  @doc """
  Render a list of trajectories as compact plain text suitable for the
  LLM prompt. Each step is one line; large payloads are truncated.
  """
  @spec summarize_trajectories([map()]) :: String.t()
  def summarize_trajectories(trajectories) when is_list(trajectories) do
    trajectories
    |> Enum.with_index(1)
    |> Enum.map_join("\n\n", fn {tr, i} -> summarize_one(tr, i) end)
  end

  defp summarize_one(%{run: run, steps: steps, tool_calls: tool_calls, failures: failures}, idx) do
    header =
      "== Run #{idx} (id=#{short(run.id)}) ==\n" <>
        "  user_input: #{truncate(run.user_input)}\n" <>
        "  status: #{run.status}\n" <>
        "  final_answer: #{truncate(run.final_answer)}\n" <>
        "  errors: #{truncate(inspect(run.errors))}"

    tool_call_by_step = Enum.group_by(tool_calls, & &1.step_id)

    step_lines =
      steps
      |> Enum.take(@default_max_steps_per_run)
      |> Enum.map_join("\n", &format_step(&1, tool_call_by_step))

    failure_lines =
      case failures do
        [] ->
          ""

        list ->
          "\n  -- failure occurrences --\n" <>
            Enum.map_join(list, "\n", fn occ ->
              mode = (occ.failure_mode && occ.failure_mode.slug) || "unclassified"
              "  ! [#{mode}] #{truncate(occ.reason)}"
            end)
      end

    header <> "\n  -- trajectory --\n" <> step_lines <> failure_lines
  end

  defp format_step(%Step{} = s, tool_call_by_step) do
    payload = truncate(inspect(s.payload))
    base = "  ##{s.idx} [#{s.kind}] #{payload}"

    case Map.get(tool_call_by_step, s.id, []) do
      [] ->
        base

      calls ->
        tail =
          Enum.map_join(calls, "; ", fn tc ->
            outcome =
              cond do
                is_binary(tc.error) and tc.error != "" -> "ERROR=#{truncate(tc.error)}"
                true -> "ok"
              end

            "tool=#{tc.tool_name} #{outcome} (#{tc.latency_ms || "?"}ms)"
          end)

        base <> "\n      → " <> tail
    end
  end

  @doc """
  Call the LLM with the given trajectories and parse the JSON
  diagnosis. The trajectories list must be non-empty.

  Options:
    * `:adapter` — defaults to `LLM.Adapter.default/0`
    * `:max_completion_tokens` — defaults to #{@default_max_completion_tokens}
  """
  @spec diagnose([map()], keyword()) ::
          {:ok, diagnosis()} | {:error, term()}
  def diagnose([], _opts), do: {:error, :no_trajectories}

  def diagnose(trajectories, opts) when is_list(trajectories) do
    adapter = Keyword.get(opts, :adapter, LLM.Adapter.default())
    max_tokens = Keyword.get(opts, :max_completion_tokens, @default_max_completion_tokens)

    user_msg =
      "Diagnose the shared root cause of these failed runs:\n\n" <>
        summarize_trajectories(trajectories)

    messages = [
      %{"role" => "system", "content" => @system_prompt},
      %{"role" => "user", "content" => user_msg}
    ]

    case adapter.chat(messages, temperature: 0.1, max_completion_tokens: max_tokens) do
      {:ok, %Response{content: text}} when is_binary(text) and text != "" ->
        parse(text, trajectories)

      {:ok, _} ->
        {:error, :empty_diagnostics_response}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e ->
      Logger.warning("Diagnostics: exception in diagnose/2: #{Exception.message(e)}")
      {:error, {:diagnose_exception, Exception.message(e)}}
  end

  # ----- JSON parsing -----

  defp parse(text, trajectories) do
    cleaned = text |> String.trim() |> strip_fence()

    with {:ok, map} <- Jason.decode(cleaned),
         {:ok, diag} <- shape(map) do
      run_ids = Enum.map(trajectories, fn %{run: r} -> r.id end)
      {:ok, Map.put(diag, :run_ids, run_ids)}
    else
      {:error, %Jason.DecodeError{} = err} -> {:error, {:json_parse, Exception.message(err)}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp shape(%{
         "summary" => summary,
         "narrative" => narrative,
         "recurring_pattern" => pattern,
         "suggested_fix_kind" => kind,
         "confidence" => confidence
       })
       when is_binary(summary) and is_binary(narrative) and is_binary(pattern) and
              is_binary(kind) and is_number(confidence) do
    {:ok,
     %{
       summary: String.slice(summary, 0, 200),
       narrative: String.slice(narrative, 0, 1500),
       recurring_pattern: String.slice(pattern, 0, 300),
       suggested_fix_kind: kind,
       confidence: clamp(confidence, 0.0, 1.0)
     }}
  end

  defp shape(_), do: {:error, :bad_diagnostics_shape}

  defp strip_fence(text) do
    case Regex.run(~r/^```(?:json)?\s*(.*?)\s*```$/s, text, capture: :all_but_first) do
      [inner] -> inner
      _ -> text
    end
  end

  defp clamp(n, lo, hi) when is_number(n), do: n |> max(lo) |> min(hi)

  # ----- Misc -----

  defp truncate(nil), do: ""
  defp truncate(s) when is_binary(s), do: String.slice(s, 0, @max_payload_chars)
  defp truncate(other), do: other |> inspect() |> String.slice(0, @max_payload_chars)

  defp short(id) when is_binary(id), do: String.slice(id, 0, 8)
  defp short(_), do: "?"
end
