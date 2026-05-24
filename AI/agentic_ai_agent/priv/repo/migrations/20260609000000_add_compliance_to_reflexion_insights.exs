defmodule AgenticAiAgent.Repo.Migrations.AddComplianceToReflexionInsights do
  use Ecto.Migration

  def change do
    alter table(:reflexion_insights) do
      # Did the agent actually act on this critique mid-run?
      #   "complied"   — next critique pivoted to a different theme (or none)
      #   "ignored"    — same theme recurred but didn't reach escalation
      #   "escalated"  — same theme recurred ≥ threshold times → stronger msg
      #                  was injected to force a strategy change
      #   nil          — too early to tell (e.g., only one critique in run)
      add :compliance_outcome, :string

      # Cumulative count of consecutive critiques that flagged the same
      # theme. Useful to spot "the agent stays slightly broken" patterns
      # short of full escalation.
      add :noncompliance_count, :integer, default: 0

      # When escalation fired, which iteration of the parent run was it?
      # Lets the operator open the run trace and see the moment the
      # runtime gave up on advisory mode.
      add :escalated_at_iteration, :integer
    end

    create index(:reflexion_insights, [:compliance_outcome])
  end
end
