defmodule AgenticAiAgent.Repo.Migrations.CreateMemories do
  use Ecto.Migration

  def change do
    create table(:memories, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # Memory Schema (see docs/eval.md)
      add :kind, :string, null: false, default: "semantic"
      add :source, :string
      add :content, :text, null: false
      add :embedding, :binary
      add :dim, :integer
      add :embedding_model, :string

      add :metadata, :map
      add :confidence, :float, default: 1.0
      add :sensitivity, :string, default: "internal"
      add :retention_days, :integer
      add :update_rule, :string, default: "append_only"
      add :deletion_rule, :string, default: "manual"

      add :last_accessed_at, :utc_datetime
      add :access_count, :integer, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:memories, [:kind])
    create index(:memories, [:source])
    create index(:memories, [:sensitivity])
    create index(:memories, [:inserted_at])
  end
end
