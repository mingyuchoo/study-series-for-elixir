defmodule Core.Schema.Agent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "agents" do
    field(:type, Ecto.Enum, values: [:supervisor, :worker])
    field(:name, :string)
    field(:display_name, :string)
    field(:description, :string)
    field(:system_prompt, :string)
    field(:model, :string, default: "gpt-5-mini")
    field(:temperature, :float, default: 1.0)
    field(:max_iterations, :integer, default: 10)
    field(:enabled_tools, {:array, :string}, default: [])
    field(:config, :map, default: %{})
    field(:status, Ecto.Enum, values: [:active, :disabled], default: :active)
    field(:created_from_markdown, :boolean, default: false)
    field(:markdown_path, :string)

    has_many(:supervised_conversations, Core.Schema.Conversation,
      foreign_key: :supervisor_agent_id
    )

    has_many(:memories, Core.Schema.AgentMemory)
    has_many(:supervised_tasks, Core.Schema.AgentTask, foreign_key: :supervisor_id)
    has_many(:worker_tasks, Core.Schema.AgentTask, foreign_key: :worker_id)
    has_many(:outgoing_interactions, Core.Schema.AgentInteraction, foreign_key: :from_agent_id)
    has_many(:incoming_interactions, Core.Schema.AgentInteraction, foreign_key: :to_agent_id)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(agent, attrs) do
    agent
    |> cast(attrs, [
      :type,
      :name,
      :display_name,
      :description,
      :system_prompt,
      :model,
      :temperature,
      :max_iterations,
      :enabled_tools,
      :config,
      :status,
      :created_from_markdown,
      :markdown_path
    ])
    |> validate_required([:type, :name])
    |> validate_inclusion(:type, [:supervisor, :worker])
    |> validate_inclusion(:status, [:active, :disabled])
    |> validate_number(:temperature, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 2.0)
    |> validate_number(:max_iterations, greater_than: 0)
    |> unique_constraint(:name)
  end
end
