defmodule AgenticAiAgent.Failures.FailureMode do
  @moduledoc """
  Catalog entry for a known failure shape. Authored as YAML under
  `priv/failures/` and synced into this table. Matches the Failure Mode
  Catalog row in `docs/eval.md` (§12).
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias AgenticAiAgent.Failures.FailureOccurrence

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @severities ~w(low medium high critical)
  @failure_types ~w(planning llm tool sandbox mcp memory policy infrastructure unknown)

  schema "failure_modes" do
    field :slug, :string
    field :name, :string
    field :failure_type, :string, default: "unknown"
    field :severity, :string, default: "medium"
    field :trigger_condition, :string
    field :example, :string
    field :expected_recovery, :string
    field :detection_method, :string
    field :related_test_cases, {:array, :string}, default: []
    field :metadata, :map

    has_many :occurrences, FailureOccurrence

    timestamps(type: :utc_datetime)
  end

  def severities, do: @severities
  def failure_types, do: @failure_types

  @castable ~w(slug name failure_type severity trigger_condition example expected_recovery detection_method related_test_cases metadata)a

  def changeset(mode, attrs) do
    mode
    |> cast(attrs, @castable)
    |> validate_required([:slug, :name])
    |> validate_inclusion(:severity, @severities)
    |> validate_inclusion(:failure_type, @failure_types)
    |> unique_constraint(:slug)
  end
end
