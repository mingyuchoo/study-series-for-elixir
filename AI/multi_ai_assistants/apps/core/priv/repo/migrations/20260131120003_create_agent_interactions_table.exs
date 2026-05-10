defmodule Core.Repo.Migrations.CreateAgentInteractionsTable do
  use Ecto.Migration

  def change do
    create table(:agent_interactions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :conversation_id, references(:conversations, type: :binary_id, on_delete: :delete_all),
          null: false
      add :from_agent_id, references(:agents, type: :binary_id, on_delete: :nothing),
          null: false
      add :to_agent_id, references(:agents, type: :binary_id, on_delete: :nothing),
          null: false
      add :interaction_type, :string, null: false
      add :message_content, :text

      timestamps(inserted_at: :inserted_at, updated_at: false, type: :utc_datetime)
    end

    create index(:agent_interactions, [:conversation_id])
    create index(:agent_interactions, [:from_agent_id])
    create index(:agent_interactions, [:to_agent_id])
    create index(:agent_interactions, [:interaction_type])
  end
end
