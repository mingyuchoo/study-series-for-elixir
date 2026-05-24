defmodule AgenticAiAgent.Repo.Migrations.AddMcpTransport do
  use Ecto.Migration

  def change do
    alter table(:mcp_servers) do
      add :transport, :string, null: false, default: "stdio"
      add :url, :string
      add :headers, :map, null: false, default: %{}
    end
  end
end
