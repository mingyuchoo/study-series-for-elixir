defmodule Core.Repo.Migrations.AddLocalPermissionLevelToMcps do
  use Ecto.Migration

  @filesystem_id "1f41c2c9-74d6-4b74-9796-9c4efdddfd4b"
  @desktop_commander_id "19e64761-d22a-48f2-9fd7-3c7f826f9f09"

  def up do
    alter table(:mcps) do
      add(:local_permission_level, :string, null: false, default: "none")
    end

    execute("""
    INSERT INTO mcps (id, name, command, args, env, enabled, local_permission_level, inserted_at, updated_at)
    SELECT
      '#{@filesystem_id}',
      'filesystem',
      'npx',
      '["-y","@modelcontextprotocol/server-filesystem","${MCP_FILESYSTEM_ROOT}"]',
      '{"MCP_FILESYSTEM_ROOT":"${MCP_FILESYSTEM_ROOT}"}',
      1,
      'read_only',
      CURRENT_TIMESTAMP,
      CURRENT_TIMESTAMP
    WHERE NOT EXISTS (SELECT 1 FROM mcps WHERE name = 'filesystem')
    """)

    execute("""
    INSERT INTO mcps (id, name, command, args, env, enabled, local_permission_level, inserted_at, updated_at)
    SELECT
      '#{@desktop_commander_id}',
      'desktop-commander',
      'npx',
      '["-y","@wonderwhy-er/desktop-commander"]',
      '{}',
      1,
      'full',
      CURRENT_TIMESTAMP,
      CURRENT_TIMESTAMP
    WHERE NOT EXISTS (SELECT 1 FROM mcps WHERE name = 'desktop-commander')
    """)
  end

  def down do
    execute(
      "DELETE FROM mcps WHERE name = 'desktop-commander' AND id = '#{@desktop_commander_id}'"
    )

    execute("DELETE FROM mcps WHERE name = 'filesystem' AND id = '#{@filesystem_id}'")

    alter table(:mcps) do
      remove(:local_permission_level)
    end
  end
end
