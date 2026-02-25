defmodule Core.Schema.AgentInteraction do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "agent_interactions" do
    field(:interaction_type, Ecto.Enum,
      values: [:task_delegation, :result_return, :status_update]
    )

    field(:message_content, :map)

    belongs_to(:conversation, Core.Schema.Conversation)
    belongs_to(:from_agent, Core.Schema.Agent)
    belongs_to(:to_agent, Core.Schema.Agent)

    timestamps(inserted_at: :inserted_at, updated_at: false, type: :utc_datetime)
  end

  @doc false
  def changeset(agent_interaction, attrs) do
    agent_interaction
    |> cast(attrs, [
      :conversation_id,
      :from_agent_id,
      :to_agent_id,
      :interaction_type,
      :message_content
    ])
    |> validate_required([:conversation_id, :from_agent_id, :to_agent_id, :interaction_type])
    |> validate_inclusion(:interaction_type, [:task_delegation, :result_return, :status_update])
    |> foreign_key_constraint(:conversation_id)
    |> foreign_key_constraint(:from_agent_id)
    |> foreign_key_constraint(:to_agent_id)
  end
end
