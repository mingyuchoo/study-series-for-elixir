defmodule Productivity.Repo.Migrations.CreateItems do
  use Ecto.Migration

  def change do
    create table(:items, prefix: :productivity) do
      add :title, :string
      add :description, :string, null: true
      add :status, :string

      # Note: Cross-schema foreign key constraint removed for Umbrella app compatibility
      # User validation is handled at the application level in the Item changeset
      add :user_id, :integer, null: true
      add :list_id, references(:lists, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end

    create index(:items, [:list_id], prefix: :productivity)
    create index(:items, [:user_id], prefix: :productivity)
  end
end
