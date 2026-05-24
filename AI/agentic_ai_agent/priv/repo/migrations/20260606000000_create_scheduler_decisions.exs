defmodule AgenticAiAgent.Repo.Migrations.CreateSchedulerDecisions do
  use Ecto.Migration

  def change do
    create table(:scheduler_decisions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # What the scheduler considered/did. Canonical values today:
      #   applied / rolled_back / blocked_safety / blocked_perf /
      #   would_apply / would_rollback / rollback_safety_warning /
      #   no_previous_version / restore_failed
      add :action, :string, null: false

      # True when the scheduler was in dry-run mode and DID NOT mutate
      # anything. False for real applies / rollbacks.
      add :dry_run, :boolean, null: false, default: false

      add :card_slug, :string

      add :proposal_id,
          references(:improvement_proposals, type: :binary_id, on_delete: :nilify_all)

      # Short human-readable summary line. Limited to a sensible length
      # so list-views can render it without clipping.
      add :detail, :string

      # Free-form payload: score_delta, ratios, violation summaries.
      add :metadata, :map

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:scheduler_decisions, [:action, :inserted_at])
    create index(:scheduler_decisions, [:card_slug, :inserted_at])
    create index(:scheduler_decisions, [:dry_run])
  end
end
