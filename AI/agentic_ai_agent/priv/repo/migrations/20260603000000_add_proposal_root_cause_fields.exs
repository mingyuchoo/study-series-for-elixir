defmodule AgenticAiAgent.Repo.Migrations.AddProposalRootCauseFields do
  use Ecto.Migration

  def change do
    alter table(:improvement_proposals) do
      # Full LLM root-cause analysis text. Stored verbatim so operators
      # can inspect the diagnostic reasoning behind a proposal.
      add :root_cause, :text

      # One-line headline ("step 3: web_search returned empty + planner
      # didn't re-plan"). Used for compact display in the proposal list.
      add :root_cause_summary, :string

      # Run IDs whose step sequences fed the diagnosis. Mirrors the
      # storage shape of supporting_run_ids on the same table.
      add :root_cause_run_ids, {:array, :string}, default: []
    end
  end
end
