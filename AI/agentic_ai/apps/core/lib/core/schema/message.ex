defmodule Core.Schema.Message do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "messages" do
    field(:role, Ecto.Enum, values: [:system, :user, :assistant, :tool])
    field(:content, :string)
    field(:tool_calls, {:array, :map}, default: [])
    field(:tool_call_id, :string)
    field(:tokens_used, :integer)

    belongs_to(:conversation, Core.Schema.Conversation)
    belongs_to(:agent, Core.Schema.Agent)
    belongs_to(:agent_task, Core.Schema.AgentTask)

    timestamps(type: :utc_datetime)
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [
      :role,
      :content,
      :tool_calls,
      :tool_call_id,
      :tokens_used,
      :conversation_id,
      :agent_id,
      :agent_task_id
    ])
    |> validate_required([:role, :content, :conversation_id])
    |> foreign_key_constraint(:conversation_id)
    |> foreign_key_constraint(:agent_id)
    |> foreign_key_constraint(:agent_task_id)
  end
end
