defmodule Discuss.Repo.Migrations.AddDeletedAtToTopics do
  use Ecto.Migration

  def change do
    alter table(:topics) do
      add :deleted_at, :utc_datetime, null: true
    end
  end
end
