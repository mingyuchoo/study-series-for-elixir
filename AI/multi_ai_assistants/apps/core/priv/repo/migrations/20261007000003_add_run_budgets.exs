defmodule Core.Repo.Migrations.AddRunBudgets do
  use Ecto.Migration

  def change do
    alter table(:agent_runs) do
      add(:model_calls, :integer, null: false, default: 0)
      add(:tool_calls, :integer, null: false, default: 0)
      add(:tokens_used, :integer, null: false, default: 0)
    end
  end
end
