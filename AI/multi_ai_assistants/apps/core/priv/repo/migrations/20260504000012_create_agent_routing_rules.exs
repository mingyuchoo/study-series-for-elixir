defmodule Core.Repo.Migrations.CreateAgentRoutingRules do
  use Ecto.Migration

  def change do
    create table(:agent_routing_rules, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:rule_type, :string, null: false)
      add(:domain, :string, null: false)
      add(:pattern, :string, null: false)
      add(:enabled, :boolean, default: true)

      timestamps(type: :utc_datetime)
    end

    create(unique_index(:agent_routing_rules, [:rule_type, :domain, :pattern]))
    create(index(:agent_routing_rules, [:rule_type, :enabled]))
  end
end
