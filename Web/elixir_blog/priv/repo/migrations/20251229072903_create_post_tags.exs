defmodule ElixirBlog.Repo.Migrations.CreatePostTags do
  use Ecto.Migration

  def change do
    create table(:post_tags) do
      add :post_id, references(:posts, on_delete: :delete_all), null: false
      add :tag_id, references(:tags, on_delete: :delete_all), null: false
      add :inserted_at, :utc_datetime, null: false, default: fragment("CURRENT_TIMESTAMP")
    end

    create index(:post_tags, [:post_id])
    create index(:post_tags, [:tag_id])
    create unique_index(:post_tags, [:post_id, :tag_id])
  end
end
