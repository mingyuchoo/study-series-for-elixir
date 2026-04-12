defmodule ElixirBlog.Repo.Migrations.CreateTags do
  use Ecto.Migration

  def change do
    create table(:tags) do
      add :name, :string, null: false, size: 100
      add :slug, :string, null: false, size: 100

      timestamps()
    end

    create unique_index(:tags, [:name])
    create unique_index(:tags, [:slug])
  end
end
