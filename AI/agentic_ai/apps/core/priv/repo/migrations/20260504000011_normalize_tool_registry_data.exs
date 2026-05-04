defmodule Core.Repo.Migrations.NormalizeToolRegistryData do
  use Ecto.Migration

  @agent_avatars [
    {"main_supervisor", "avatar-01.png"},
    {"research_worker", "avatar-02.png"},
    {"knowledge_worker", "avatar-03.png"},
    {"calculator_worker", "avatar-04.png"},
    {"restructure_worker", "avatar-05.png"},
    {"system_worker", "avatar-06.png"}
  ]

  def up do
    execute("UPDATE tools SET enabled = 1 WHERE enabled IN ('true', 'TRUE', '1')")
    execute("UPDATE tools SET enabled = 0 WHERE enabled IN ('false', 'FALSE', '0')")

    Enum.each(@agent_avatars, fn {name, avatar_path} ->
      execute(
        "UPDATE agents SET avatar_path = '#{avatar_path}', updated_at = CURRENT_TIMESTAMP WHERE name = '#{name}' AND (avatar_path IS NULL OR avatar_path = '')"
      )
    end)
  end

  def down do
    :ok
  end
end
