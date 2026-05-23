defmodule Mix.Tasks.Agent.Eval do
  @shortdoc "Run the golden dataset for an agentic card and print a scored report"
  @moduledoc """
  Usage:

      mix agent.eval                       # uses card slug "default"
      mix agent.eval --card mycard
      mix agent.eval --golden priv/eval/golden/smoke.jsonl
      mix agent.eval --threshold 0.8

  The task starts the application (so Repo, Runtime supervision, tool
  registry, etc. are live), loads the JSONL golden file, executes each case
  via `Agent.Runtime`, scores it with the heuristic `Rubric`, persists an
  `EvalRun` plus one `EvalCase` per scenario, prints a summary, and exits
  with a non-zero status if the run's average score is below the threshold.
  """

  use Mix.Task

  alias AgenticAiAgent.Eval

  @impl Mix.Task
  def run(argv) do
    {opts, _, _} =
      OptionParser.parse(argv,
        strict: [card: :string, golden: :string, threshold: :float],
        aliases: [c: :card, g: :golden, t: :threshold]
      )

    card = Keyword.get(opts, :card, "default")
    Mix.Task.run("app.start")

    run_opts =
      [golden: Keyword.get(opts, :golden), pass_threshold: Keyword.get(opts, :threshold)]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    case Eval.run_card(card, run_opts) do
      {:ok, eval_run} -> report_and_exit(eval_run)
      {:error, reason} -> Mix.shell().error("eval failed: #{inspect(reason)}") |> tap(fn _ -> exit({:shutdown, 1}) end)
    end
  end

  defp report_and_exit(eval_run) do
    Mix.shell().info("")
    Mix.shell().info(IO.ANSI.bright() <> "Eval run #{String.slice(eval_run.id, 0, 8)}" <> IO.ANSI.reset())
    Mix.shell().info("  golden:      #{eval_run.golden_path}")
    Mix.shell().info("  threshold:   #{eval_run.pass_threshold}")
    Mix.shell().info("  cases:       #{eval_run.total_cases} (#{eval_run.passed_cases} passed)")
    Mix.shell().info("  avg_score:   #{format_score(eval_run.average_score)}")
    Mix.shell().info("")

    for c <- eval_run.cases do
      icon = if c.passed, do: "✓", else: "✗"
      colour = if c.passed, do: IO.ANSI.green(), else: IO.ANSI.red()

      Mix.shell().info(
        "  #{colour}#{icon}#{IO.ANSI.reset()} #{pad(c.case_id, 24)}  " <>
          format_score(c.total_score) <>
          "  " <>
          dimension_summary(c.scores) <>
          (if c.notes, do: "  (#{c.notes})", else: "")
      )
    end

    Mix.shell().info("")
    Mix.shell().info("Run details: /evals/#{eval_run.id}")

    threshold = eval_run.pass_threshold || 0.7
    avg = eval_run.average_score || 0.0

    if avg < threshold do
      Mix.shell().error("Average #{format_score(avg)} < threshold #{threshold}")
      exit({:shutdown, 1})
    end
  end

  defp format_score(nil), do: "—"
  defp format_score(n) when is_number(n), do: :io_lib.format("~5.3f", [n]) |> List.to_string()

  defp dimension_summary(nil), do: ""

  defp dimension_summary(scores) do
    ~w(correctness completeness tool_use_quality safety efficiency)
    |> Enum.map_join(" ", fn k -> "#{String.slice(k, 0, 1)}:#{format_score(Map.get(scores, k, 0.0))}" end)
  end

  defp pad(s, n) do
    s = to_string(s)
    if String.length(s) >= n, do: s, else: s <> String.duplicate(" ", n - String.length(s))
  end
end
