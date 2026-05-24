defmodule AgenticAiAgent.Repo.Migrations.CreateNotifications do
  use Ecto.Migration

  def change do
    create table(:notifications, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # What happened. Free-form string today; common kinds:
      #   "auto_promote" / "auto_rollback" / "safety_blocked" / "dry_run"
      add :kind, :string, null: false
      add :subject, :string, null: false
      add :body, :text

      # Optional references — strings (not FKs) so cleanup of source rows
      # doesn't cascade-delete the notification record.
      add :proposal_id, :string
      add :run_id, :string
      add :card_slug, :string

      add :read_at, :utc_datetime

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:notifications, [:read_at, :inserted_at])
    create index(:notifications, [:kind, :inserted_at])
  end
end
