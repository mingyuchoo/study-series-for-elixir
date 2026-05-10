defmodule Core.Schema.VectorRag do
  use Ecto.Schema
  import Ecto.Changeset

  alias Core.Schema.VectorRagChunk

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "vector_rags" do
    field(:name, :string)
    field(:description, :string)
    field(:source_filename, :string)
    field(:index_path, :string)
    field(:embedding_dim, :integer, default: 384)
    field(:chunk_count, :integer, default: 0)
    field(:enabled, :boolean, default: true)

    has_many(:chunks, VectorRagChunk)

    timestamps(type: :utc_datetime)
  end

  def changeset(vector_rag, attrs) do
    vector_rag
    |> cast(attrs, [
      :name,
      :description,
      :source_filename,
      :index_path,
      :embedding_dim,
      :chunk_count,
      :enabled
    ])
    |> validate_required([:name, :embedding_dim, :chunk_count])
    |> validate_number(:embedding_dim, greater_than: 0)
    |> validate_number(:chunk_count, greater_than_or_equal_to: 0)
    |> unique_constraint(:name)
  end
end
