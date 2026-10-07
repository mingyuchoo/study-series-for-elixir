defmodule Core.Agent.TaskRouter do
  @moduledoc "Loads routing rules and delegates worker selection to the pure domain service."

  require Logger
  alias AgentDomain.TaskRouter, as: DomainTaskRouter
  alias Core.Agent.RoutingRules

  def select_worker(request, workers) do
    case select_worker_with_score(request, workers) do
      {:ok, worker, _score} -> {:ok, worker}
      error -> error
    end
  end

  def select_worker_with_score(_request, []) do
    Logger.warning("No workers available for task routing")
    {:error, :no_workers_available}
  end

  def select_worker_with_score(request, workers) do
    rules = RoutingRules.list_active_rules()
    Logger.info("Routing task: #{request}")
    Logger.info("Available workers: #{inspect(Enum.map(workers, & &1.name))}")

    case DomainTaskRouter.select_worker_with_score(request, workers, rules) do
      {:ok, worker, score} = result ->
        Logger.info("Selected worker: #{worker.name} (score: #{score})")
        result

      error ->
        error
    end
  end
end
