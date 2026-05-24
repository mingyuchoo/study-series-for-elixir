defmodule AgenticAiAgent.Repo.Migrations.AddRunWorkflowState do
  use Ecto.Migration

  def change do
    alter table(:runs) do
      # Name of the workflow's current state (e.g. "planning", "acting").
      # Nullable: runs without an enforced workflow leave it nil.
      add :workflow_state, :string
    end
  end
end
