defmodule AgenticAiAgent.Repo.Migrations.AddWorkflowEnforceAndActions do
  use Ecto.Migration

  def change do
    alter table(:workflow_graphs) do
      add :enforce, :boolean, default: false, null: false
      add :allowed_actions, :map
      add :required_evidence, :map
    end
  end
end
