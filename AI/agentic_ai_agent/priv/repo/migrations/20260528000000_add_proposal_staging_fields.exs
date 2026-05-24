defmodule AgenticAiAgent.Repo.Migrations.AddProposalStagingFields do
  use Ecto.Migration

  def change do
    alter table(:improvement_proposals) do
      # Slug of the temporary staging card (e.g. "default-staging").
      add :staging_slug, :string

      # Stored as strings to avoid an FK to eval_runs (which may be deleted
      # via cleanup); we just need to find/show them by id.
      add :staging_eval_run_id, :string
      add :baseline_eval_run_id, :string

      add :baseline_score, :float
      add :staging_score, :float
      add :score_delta, :float
    end

    create index(:improvement_proposals, [:staging_slug])
  end
end
