defmodule AgenticAiAgent.Eval do
  @moduledoc """
  Public API for the evaluation layer. A typical run looks like:

      {:ok, eval_run} = Eval.run_card("default")

  which loads the card's golden dataset (`evaluation_mapping.golden_dataset`),
  runs each case end-to-end via `Agent.Runtime`, scores it with the
  `Rubric`, and persists everything for the `/evals` dashboard and the
  `mix agent.eval` task to consume.
  """

  import Ecto.Query

  alias AgenticAiAgent.{Conversation, Design, Repo, Traces}
  alias AgenticAiAgent.Agent.Runtime
  alias AgenticAiAgent.Eval.{EvalCase, EvalRun, Rubric}

  @case_timeout_ms 60_000

  # ----- Queries -----

  def list_eval_runs(limit \\ 25) do
    EvalRun
    |> order_by([r], desc: r.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  def get_eval_run!(id), do: Repo.get!(EvalRun, id)

  def get_eval_run_with_cases!(id) do
    EvalRun
    |> Repo.get!(id)
    |> Repo.preload(cases: from(c in EvalCase, order_by: c.inserted_at))
  end

  def list_cases(eval_run_id) do
    EvalCase
    |> where([c], c.eval_run_id == ^eval_run_id)
    |> order_by([c], asc: c.inserted_at)
    |> Repo.all()
  end

  # ----- Golden dataset -----

  @doc """
  Load a JSONL golden file. Returns `{:ok, [case_map]}` or `{:error, reason}`.
  Each non-empty line must be a JSON object. Relative paths are resolved from
  `priv/` if the file does not exist on the literal path.
  """
  def load_golden(path) when is_binary(path) do
    file =
      cond do
        File.exists?(path) -> path
        File.exists?(Application.app_dir(:agentic_ai_agent, path)) ->
          Application.app_dir(:agentic_ai_agent, path)
        true -> path
      end

    with {:ok, raw} <- File.read(file),
         lines <- String.split(raw, "\n", trim: true),
         {:ok, cases} <- parse_lines(lines, [], 1) do
      {:ok, cases}
    end
  end

  defp parse_lines([], acc, _n), do: {:ok, Enum.reverse(acc)}

  defp parse_lines([line | rest], acc, n) do
    case Jason.decode(line) do
      {:ok, m} when is_map(m) -> parse_lines(rest, [m | acc], n + 1)
      {:ok, _} -> {:error, {:non_object_line, n}}
      {:error, err} -> {:error, {:bad_json, n, err}}
    end
  end

  # ----- Run -----

  @doc """
  Run every case in `card.evaluation_mapping.golden_dataset` end-to-end.
  Returns `{:ok, eval_run}` on completion (even with failing cases).

  Opts:
    * `:golden` — override the file path
    * `:rubric` — override the weights map
    * `:pass_threshold` — override the card's threshold (0.0-1.0)
  """
  def run_card(card_or_slug, opts \\ [])

  def run_card(slug, opts) when is_binary(slug) do
    case Design.get_card_by_slug(slug) do
      nil -> {:error, :card_not_found}
      card -> run_card(card, opts)
    end
  end

  def run_card(%Design.AgenticCard{} = card, opts) do
    eval_map = card.evaluation_mapping || %{}
    golden = Keyword.get(opts, :golden, eval_map["golden_dataset"])
    rubric = Keyword.get(opts, :rubric) || Map.get(eval_map, "rubric") || Rubric.default_weights()
    threshold = Keyword.get(opts, :pass_threshold) || Map.get(eval_map, "pass_threshold", 0.7)

    cond do
      golden in [nil, ""] ->
        {:error, :no_golden_path}

      true ->
        with {:ok, cases} <- load_golden(golden) do
          do_run(card, golden, rubric, threshold, cases)
        end
    end
  end

  defp do_run(card, golden, rubric, threshold, cases) do
    started = DateTime.utc_now()

    eval_run =
      %EvalRun{}
      |> EvalRun.changeset(%{
        agentic_card_id: card.id,
        golden_path: golden,
        rubric: rubric,
        pass_threshold: threshold,
        started_at: started,
        total_cases: length(cases)
      })
      |> Repo.insert!()

    case_rows = Enum.map(cases, &run_one(card, eval_run, &1, rubric, threshold))

    passed = Enum.count(case_rows, & &1.passed)
    avg = (case_rows |> Enum.map(& &1.total_score) |> sum_or_nil()) / max(length(case_rows), 1)

    Repo.update!(
      EvalRun.changeset(eval_run, %{
        status: "done",
        finished_at: DateTime.utc_now(),
        total_cases: length(case_rows),
        passed_cases: passed,
        average_score: Float.round(avg, 4),
        summary: %{
          "by_task_type" => group_score_by(case_rows, & &1.task_type),
          "weights" => rubric
        }
      })
    )

    {:ok, get_eval_run_with_cases!(eval_run.id)}
  end

  defp sum_or_nil([]), do: 0.0
  defp sum_or_nil(list), do: Enum.sum(list)

  defp group_score_by(case_rows, key_fun) do
    case_rows
    |> Enum.group_by(key_fun)
    |> Map.new(fn {k, cs} ->
      avg = Enum.sum(Enum.map(cs, & &1.total_score)) / length(cs)
      {to_string(k || "_"),
       %{"count" => length(cs), "passed" => Enum.count(cs, & &1.passed), "avg_score" => Float.round(avg, 4)}}
    end)
  end

  # ----- One case -----

  defp run_one(card, eval_run, case_data, rubric, threshold) do
    case_id = case_data["id"] || "unnamed"
    input = case_data["input"] || ""
    expected_tools = case_data["expected_tools"] || []
    task_type = case_data["task_type"]

    parent = self()

    spawn(fn ->
      {:ok, conv} = Conversation.start_link(system_prompt: build_system_prompt(card))

      {:ok, _runtime} =
        Runtime.start(
          conversation: conv,
          card: card,
          user_input: input,
          subscriber: parent,
          max_steps: case_data["max_steps"] || 12
        )
    end)

    {final_answer, run_id, status} = await_run(@case_timeout_ms)

    {run, steps, tool_calls} = load_trace(run_id)

    scores = Rubric.score(case_data, run, steps, tool_calls)
    total = Rubric.total(scores, rubric)
    passed? = total >= threshold and status != :timeout

    notes =
      cond do
        status == :timeout -> "timed out waiting for runtime"
        status == :failed -> "runtime returned :failed"
        true -> nil
      end

    %EvalCase{}
    |> EvalCase.changeset(%{
      eval_run_id: eval_run.id,
      run_id: run_id,
      case_id: case_id,
      task_type: task_type,
      input: input,
      expected: case_data["expected"],
      expected_tools: expected_tools,
      final_answer: final_answer,
      scores: scores,
      total_score: Float.round(total, 4),
      passed: passed?,
      notes: notes
    })
    |> Repo.insert!()
  end

  defp await_run(timeout) do
    # Drain runtime messages until :final or :failed, ignoring intermediates.
    do_await(timeout, nil)
  end

  defp do_await(timeout, run_id) do
    receive do
      {:agent, :started, rid} -> do_await(timeout, rid)
      {:agent, :final, content, rid} -> {content, rid, :done}
      {:agent, :failed, _reason, rid} -> {nil, rid, :failed}
      _other -> do_await(timeout, run_id)
    after
      timeout -> {nil, run_id, :timeout}
    end
  end

  defp load_trace(nil), do: {nil, [], []}

  defp load_trace(run_id) do
    {Traces.get_run!(run_id), Traces.list_steps(run_id), Traces.list_tool_calls(run_id)}
  rescue
    _ -> {nil, [], []}
  end

  defp build_system_prompt(card) do
    [
      "You are #{card.name}.",
      card.role,
      card.goal
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n\n")
  end
end
