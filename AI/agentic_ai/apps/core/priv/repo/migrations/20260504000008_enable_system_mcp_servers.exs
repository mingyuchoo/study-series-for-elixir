defmodule Core.Repo.Migrations.EnableSystemMcpServers do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE mcps
    SET enabled = 1, updated_at = CURRENT_TIMESTAMP
    WHERE name IN ('filesystem', 'desktop-commander')
    """)
  end

  def down do
    execute("""
    UPDATE mcps
    SET enabled = 0, updated_at = CURRENT_TIMESTAMP
    WHERE name = 'desktop-commander'
    """)
  end
end
