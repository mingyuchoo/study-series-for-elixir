defmodule Core.Schema.VectorRagChunk do
  use Ecto.Schema
  import Ecto.Changeset

  alias Core.Schema.VectorRag

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "vector_rag_chunks" do
    field(:position, :integer)
    field(:content, :string)

    belongs_to(:vector_rag, VectorRag)

    timestamps(type: :utc_datetime)
  end

  def changeset(chunk, attrs) do
    chunk
    |> cast(attrs, [:vector_rag_id, :position, :content])
    |> validate_required([:vector_rag_id, :position, :content])
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:vector_rag_id)
    |> unique_constraint([:vector_rag_id, :position])
  end
end
