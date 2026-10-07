defmodule AgentDomain.RoutingEval do
  @moduledoc "Evaluates labeled routing cases against a supplied rule snapshot."

  alias AgentDomain.TaskRouter

  def evaluate(workers, cases, rules) do
    workers =
      Enum.map(workers, fn worker ->
        %{
          name: worker["name"],
          description: worker["description"],
          enabled_tools: worker["enabled_tools"]
        }
      end)

    results =
      Enum.map(cases, fn item ->
        actual =
          case TaskRouter.select_worker(item["request"], workers, rules) do
            {:ok, worker} -> worker.name
            {:error, _} -> nil
          end

        %{
          request: item["request"],
          expected: item["expected"],
          actual: actual,
          passed?: actual == item["expected"]
        }
      end)

    %{passed: Enum.count(results, & &1.passed?), total: length(results), results: results}
  end
end
