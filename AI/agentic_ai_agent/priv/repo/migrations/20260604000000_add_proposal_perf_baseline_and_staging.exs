defmodule AgenticAiAgent.Repo.Migrations.AddProposalPerfBaselineAndStaging do
  use Ecto.Migration

  def change do
    alter table(:improvement_proposals) do
      # Baseline (current production card) — captured at stage! time from
      # the latest done eval_run for the target slug.
      add :baseline_cost_micro_usd, :integer
      add :baseline_latency_ms, :integer

      # Staging (proposed card) — captured at record_staging_finish! time
      # from the staging eval_run's case-level traces.
      add :staging_cost_micro_usd, :integer
      add :staging_latency_ms, :integer
    end
  end
end
