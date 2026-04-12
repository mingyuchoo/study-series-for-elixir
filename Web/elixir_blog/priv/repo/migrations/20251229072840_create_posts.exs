defmodule ElixirBlog.Repo.Migrations.CreatePosts do
  use Ecto.Migration

  def change do
    create table(:posts) do
      add :slug, :string, null: false
      add :title, :string, null: false, size: 500
      add :author, :string, null: false
      add :summary, :text, null: false
      add :thumbnail, :string, null: false
      add :published_at, :utc_datetime, null: false
      add :is_popular, :boolean, default: false, null: false
      add :reading_time, :integer, null: false
      add :content_path, :string, null: false

      timestamps()
    end

    create unique_index(:posts, [:slug])
    create unique_index(:posts, [:content_path])
    create index(:posts, [:published_at])
    create index(:posts, [:is_popular])
  end
end
