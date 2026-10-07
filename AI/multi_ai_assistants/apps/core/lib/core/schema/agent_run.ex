defmodule Core.Schema.AgentRun do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "agent_runs" do
    field(:user_request, :string)

    field(:status, Ecto.Enum,
      values: [:running, :completed, :failed, :cancelled],
      default: :running
    )

    field(:round, :integer, default: 0)
    field(:model_calls, :integer, default: 0)
    field(:tool_calls, :integer, default: 0)
    field(:tokens_used, :integer, default: 0)
    field(:transcript, :map, default: %{})
    field(:final_answer, :string)
    field(:error, :string)
    belongs_to(:conversation, Core.Schema.Conversation)
    belongs_to(:user, Core.Schema.User)
    timestamps(type: :utc_datetime)
  end

  def changeset(run, attrs) do
    run
    |> cast(attrs, [
      :conversation_id,
      :user_id,
      :user_request,
      :status,
      :round,
      :model_calls,
      :tool_calls,
      :tokens_used,
      :transcript,
      :final_answer,
      :error
    ])
    |> validate_required([:conversation_id, :user_id, :user_request, :status])
    |> foreign_key_constraint(:conversation_id)
    |> foreign_key_constraint(:user_id)
  end
end
