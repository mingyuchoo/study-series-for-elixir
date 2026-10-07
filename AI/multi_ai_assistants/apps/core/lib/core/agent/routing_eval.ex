defmodule Core.Agent.RoutingEval do
  @moduledoc "Reads a labeled routing fixture and evaluates it with current rules."

  alias AgentDomain.RoutingEval, as: DomainRoutingEval
  alias Core.Agent.RoutingRules

  def evaluate(path) do
    with {:ok, json} <- File.read(path),
         {:ok, %{"workers" => workers, "cases" => cases}} <- Jason.decode(json) do
      {:ok, DomainRoutingEval.evaluate(workers, cases, RoutingRules.list_active_rules())}
    end
  end
end
