defmodule Core.Schema.Conversation do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "conversations" do
    field(:title, :string)
    field(:system_prompt, :string)
    field(:status, Ecto.Enum, values: [:active, :archived], default: :active)
    field(:context_summary, :string)

    belongs_to(:supervisor_agent, Core.Schema.Agent)
    has_many(:messages, Core.Schema.Message)
    has_many(:agent_tasks, Core.Schema.AgentTask)
    has_many(:agent_memories, Core.Schema.AgentMemory)
    has_many(:agent_interactions, Core.Schema.AgentInteraction)

    timestamps(type: :utc_datetime)
  end

  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:title, :system_prompt, :status, :supervisor_agent_id, :context_summary])
    |> validate_required([:title])
    |> foreign_key_constraint(:supervisor_agent_id)
  end
end
