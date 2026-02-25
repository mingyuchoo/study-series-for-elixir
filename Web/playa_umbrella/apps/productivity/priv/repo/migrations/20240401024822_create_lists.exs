defmodule Productivity.Repo.Migrations.CreateLists do
  use Ecto.Migration

  def change do
    create table(:lists, prefix: :productivity) do
      add :title, :string
      add :item_count, :integer, null: false, default: 0

      # Note: Cross-schema foreign key constraint removed for Umbrella app compatibility
      # User validation is handled at the application level in the List changeset
      add :user_id, :integer, null: true

      timestamps(type: :utc_datetime)
    end

    # Create index for faster lookups
    create index(:lists, [:user_id], prefix: :productivity)
  end
end
