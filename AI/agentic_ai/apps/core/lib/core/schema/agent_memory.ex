defmodule Core.Schema.AgentMemory do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "agent_memories" do
    field(:memory_type, Ecto.Enum,
      values: [:conversation_summary, :learned_pattern, :project_context, :performance_metric]
    )

    field(:key, :string)
    field(:value, :map)
    field(:metadata, :map)
    field(:relevance_score, :float)
    field(:expires_at, :utc_datetime)

    belongs_to(:agent, Core.Schema.Agent)
    belongs_to(:conversation, Core.Schema.Conversation)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(agent_memory, attrs) do
    agent_memory
    |> cast(attrs, [
      :agent_id,
      :conversation_id,
      :memory_type,
      :key,
      :value,
      :metadata,
      :relevance_score,
      :expires_at
    ])
    |> validate_required([:agent_id, :memory_type, :key])
    |> validate_inclusion(:memory_type, [
      :conversation_summary,
      :learned_pattern,
      :project_context,
      :performance_metric
    ])
    |> foreign_key_constraint(:agent_id)
    |> foreign_key_constraint(:conversation_id)
  end
end
