defmodule Core.Repo.Migrations.SeedContext7Mcp do
  use Ecto.Migration

  @context7_id "4c99e7b5-fd1d-4dd8-9f6e-1fa3f8e2c7a7"

  def up do
    execute("""
    INSERT INTO mcps (id, name, command, args, env, enabled, inserted_at, updated_at)
    SELECT
      '#{@context7_id}',
      'context7',
      'npx',
      '["-y","@upstash/context7-mcp","--api-key","${CONTEXT7_API_KEY}"]',
      '{"CONTEXT7_API_KEY":"${CONTEXT7_API_KEY}"}',
      1,
      CURRENT_TIMESTAMP,
      CURRENT_TIMESTAMP
    WHERE NOT EXISTS (SELECT 1 FROM mcps WHERE name = 'context7')
    """)
  end

  def down do
    execute("DELETE FROM mcps WHERE name = 'context7' AND id = '#{@context7_id}'")
  end
end
