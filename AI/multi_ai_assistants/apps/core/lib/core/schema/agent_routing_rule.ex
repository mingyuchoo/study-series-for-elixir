defmodule Core.Schema.AgentRoutingRule do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "agent_routing_rules" do
    field(:rule_type, Ecto.Enum, values: [:domain_keyword, :tool_domain, :name_domain])
    field(:domain, :string)
    field(:pattern, :string)
    field(:enabled, :boolean, default: true)

    timestamps(type: :utc_datetime)
  end

  def changeset(rule, attrs) do
    rule
    |> cast(attrs, [:rule_type, :domain, :pattern, :enabled])
    |> validate_required([:rule_type, :domain, :pattern])
    |> unique_constraint([:rule_type, :domain, :pattern])
  end
end
