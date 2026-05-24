defmodule AgenticAiAgent.Repo.Migrations.CreateArtifactVersions do
  use Ecto.Migration

  def change do
    create table(:card_versions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :slug, :string, null: false
      add :body, :text, null: false
      add :sha, :string, null: false
      add :reason, :string

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:card_versions, [:slug, :inserted_at])

    create table(:skill_versions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :slug, :string, null: false
      add :body, :text, null: false
      add :sha, :string, null: false
      add :reason, :string

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:skill_versions, [:slug, :inserted_at])
  end
end
