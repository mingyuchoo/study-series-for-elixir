defmodule Core.Schema.AgentTask do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "agent_tasks" do
    field(:task_type, :string)
    field(:description, :string)
    field(:input_data, :map)
    field(:output_data, :map)

    field(:status, Ecto.Enum,
      values: [:pending, :assigned, :in_progress, :completed, :failed],
      default: :pending
    )

    field(:priority, :integer, default: 0)
    field(:started_at, :utc_datetime)
    field(:completed_at, :utc_datetime)
    field(:error_message, :string)

    belongs_to(:conversation, Core.Schema.Conversation)
    belongs_to(:supervisor, Core.Schema.Agent)
    belongs_to(:worker, Core.Schema.Agent)
    has_many(:messages, Core.Schema.Message)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(agent_task, attrs) do
    agent_task
    |> cast(attrs, [
      :conversation_id,
      :supervisor_id,
      :worker_id,
      :task_type,
      :description,
      :input_data,
      :output_data,
      :status,
      :priority,
      :started_at,
      :completed_at,
      :error_message
    ])
    |> validate_required([:conversation_id, :supervisor_id])
    |> validate_inclusion(:status, [:pending, :assigned, :in_progress, :completed, :failed])
    |> foreign_key_constraint(:conversation_id)
    |> foreign_key_constraint(:supervisor_id)
    |> foreign_key_constraint(:worker_id)
  end
end
