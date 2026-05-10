defmodule Core.Repo.Migrations.CreateVectorRags do
  use Ecto.Migration

  def change do
    create table(:vector_rags, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :source_filename, :string
      add :index_path, :string
      add :embedding_dim, :integer, null: false, default: 384
      add :chunk_count, :integer, null: false, default: 0
      add :enabled, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:vector_rags, [:name])

    create table(:vector_rag_chunks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :vector_rag_id, references(:vector_rags, type: :binary_id, on_delete: :delete_all), null: false
      add :position, :integer, null: false
      add :content, :text, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:vector_rag_chunks, [:vector_rag_id, :position])
    create index(:vector_rag_chunks, [:vector_rag_id])
  end
end
