alias Core.Agent.RoutingEval

path = Application.app_dir(:core, "priv/evals/routing.json")

case RoutingEval.evaluate(path) do
  {:ok, %{passed: passed, total: total, results: results}} ->
    Enum.each(results, fn result ->
      IO.puts(
        "#{if result.passed?, do: "PASS", else: "FAIL"} #{result.request}: #{result.actual} (expected #{result.expected})"
      )
    end)

    IO.puts("Routing accuracy: #{passed}/#{total}")
    if passed != total, do: System.halt(1)

  {:error, reason} ->
    IO.puts(:stderr, "Routing evaluation failed: #{inspect(reason)}")
    System.halt(1)
end
