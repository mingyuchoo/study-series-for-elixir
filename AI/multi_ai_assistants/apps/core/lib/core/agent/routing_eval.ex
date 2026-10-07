defmodule Core.Agent.RoutingEval do
  @moduledoc "A repeatable, labeled routing evaluation with no model dependency."

  alias Core.Agent.TaskRouter
  alias Core.Schema.Agent

  def evaluate(path) do
    with {:ok, json} <- File.read(path),
         {:ok, %{"workers" => workers, "cases" => cases}} <- Jason.decode(json) do
      workers =
        Enum.map(workers, fn worker ->
          struct(Agent, %{
            name: worker["name"],
            description: worker["description"],
            enabled_tools: worker["enabled_tools"]
          })
        end)

      results =
        Enum.map(cases, fn item ->
          actual =
            case TaskRouter.select_worker(item["request"], workers) do
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

      passed = Enum.count(results, & &1.passed?)
      {:ok, %{passed: passed, total: length(results), results: results}}
    end
  end
end
