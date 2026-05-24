defmodule AgenticAiAgent.Repo.Migrations.AddProposalAutonomousFields do
  use Ecto.Migration

  def change do
    alter table(:improvement_proposals) do
      # True if the Improver.Scheduler generated/applied this proposal
      # without human intervention.
      add :auto_promoted, :boolean, null: false, default: false

      # Set when the Scheduler reverts an auto-promoted proposal after
      # observing a post-promote regression on the next eval.
      add :rolled_back_at, :utc_datetime
      add :rolled_back_reason, :string
    end

    create index(:improvement_proposals, [:auto_promoted, :inserted_at])
  end
end
