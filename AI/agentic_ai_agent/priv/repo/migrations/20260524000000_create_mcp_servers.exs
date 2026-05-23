defmodule AgenticAiAgent.Repo.Migrations.CreateMcpServers do
  use Ecto.Migration

  def change do
    create table(:mcp_servers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :command, :string, null: false
      add :args, :map, null: false, default: %{}
      add :env, :map, null: false, default: %{}
      add :risk_level, :string, null: false, default: "medium"
      add :enabled, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:mcp_servers, [:name])
  end
end
