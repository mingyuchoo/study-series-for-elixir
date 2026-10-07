defmodule Core.Agent.RoutingEvalTest do
  use Core.DataCase, async: false

  alias Core.Agent.{RoutingEval, RoutingRules}

  test "labeled routing baseline" do
    RoutingRules.seed_defaults()
    path = Application.app_dir(:core, "priv/evals/routing.json")
    assert {:ok, %{passed: 4, total: 4}} = RoutingEval.evaluate(path)
  end
end
