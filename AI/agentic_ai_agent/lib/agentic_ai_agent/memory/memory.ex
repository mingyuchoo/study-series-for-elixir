defmodule AgenticAiAgent.Memory.Memory do
  @moduledoc """
  Long-term memory record. Implements the Memory Schema in `docs/eval.md`.
  Embedding is stored as a packed binary (float32, little-endian) so the
  whole row stays in SQLite without an extension.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @kinds ~w(semantic episodic preference task_solution profile)
  @sensitivities ~w(public internal private secret)
  @update_rules ~w(append_only overwrite_by_source overwrite_by_id)
  @deletion_rules ~w(manual ttl on_request)

  schema "memories" do
    field :kind, :string, default: "semantic"
    field :source, :string
    field :content, :string
    field :embedding, :binary
    field :dim, :integer
    field :embedding_model, :string

    field :metadata, :map
    field :confidence, :float, default: 1.0
    field :sensitivity, :string, default: "internal"
    field :retention_days, :integer
    field :update_rule, :string, default: "append_only"
    field :deletion_rule, :string, default: "manual"

    field :last_accessed_at, :utc_datetime
    field :access_count, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds
  def sensitivities, do: @sensitivities

  @castable ~w(kind source content embedding dim embedding_model metadata confidence sensitivity retention_days update_rule deletion_rule last_accessed_at access_count)a

  def changeset(memory, attrs) do
    memory
    |> cast(attrs, @castable)
    |> validate_required([:content])
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:sensitivity, @sensitivities)
    |> validate_inclusion(:update_rule, @update_rules)
    |> validate_inclusion(:deletion_rule, @deletion_rules)
    |> validate_number(:confidence, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
  end
end
