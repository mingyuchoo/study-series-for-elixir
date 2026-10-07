defmodule Core.Agent.RoutingRules do
  @moduledoc "Persists routing rules and supplies them to the pure domain service."

  import Ecto.Query
  alias AgentDomain.RoutingRules, as: DomainRoutingRules
  alias Core.Repo
  alias Core.Schema.AgentRoutingRule

  def list_active_rules do
    AgentRoutingRule
    |> where([r], r.enabled == true)
    |> Repo.all()
    |> build_rule_index()
  end

  def seed_defaults do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    rows =
      Enum.map(DomainRoutingRules.default_rules(), fn rule ->
        rule
        |> Map.merge(%{
          id: Ecto.UUID.generate(),
          enabled: true,
          inserted_at: now,
          updated_at: now
        })
      end)

    Repo.insert_all(AgentRoutingRule, rows,
      on_conflict: :nothing,
      conflict_target: [:rule_type, :domain, :pattern]
    )
  end

  defdelegate build_rule_index(rules), to: DomainRoutingRules
end
