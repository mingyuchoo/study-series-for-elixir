defmodule Core.Repo.Migrations.AddRagEmbeddingModel do
  use Ecto.Migration

  def change do
    alter table(:vector_rags) do
      add(:embedding_model, :string)
    end
  end
end
