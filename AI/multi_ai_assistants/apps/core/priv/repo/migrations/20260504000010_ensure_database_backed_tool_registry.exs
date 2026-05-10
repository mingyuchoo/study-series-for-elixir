defmodule Core.Repo.Migrations.EnsureDatabaseBackedToolRegistry do
  use Ecto.Migration

  @tools [
    {"get_current_time", "Core.Agent.Tools.DateTime"},
    {"search_web", "Core.Agent.Tools.WebSearch"},
    {"calculate", "Core.Agent.Tools.Calculator"},
    {"read_file", "Core.Agent.Tools.FileSystem"},
    {"write_file", "Core.Agent.Tools.FileSystem"},
    {"list_directory", "Core.Agent.Tools.FileSystem"},
    {"search_vector_rag", "Core.Agent.Tools.VectorRagSearch"},
    {"execute_code", "Core.Agent.Tools.CodeExecutor"},
    {"mcp_filesystem_call", "Core.Agent.Tools.Mcp"},
    {"mcp_desktop_commander_call", "Core.Agent.Tools.Mcp"},
    {"firecrawl_scrape", "Core.Agent.Tools.Firecrawl"},
    {"firecrawl_search", "Core.Agent.Tools.Firecrawl"}
  ]

  @agent_avatars [
    {"main_supervisor", "avatar-01.png"},
    {"research_worker", "avatar-02.png"},
    {"knowledge_worker", "avatar-03.png"},
    {"calculator_worker", "avatar-04.png"},
    {"restructure_worker", "avatar-05.png"},
    {"system_worker", "avatar-06.png"}
  ]

  def up do
    create_if_not_exists table(:tools, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:name, :string, null: false)
      add(:description, :text)
      add(:parameters, :text)
      add(:module_name, :string)
      add(:enabled, :boolean, default: true)

      timestamps(type: :utc_datetime)
    end

    create_if_not_exists(unique_index(:tools, [:name]))

    flush()

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    tool_rows =
      Enum.map(@tools, fn {name, module_name} ->
        %{
          id: Ecto.UUID.generate(),
          name: name,
          module_name: module_name,
          enabled: 1,
          inserted_at: now,
          updated_at: now
        }
      end)

    repo().insert_all("tools", tool_rows,
      on_conflict: {:replace, [:module_name, :enabled, :updated_at]},
      conflict_target: [:name]
    )

    Enum.each(@agent_avatars, fn {name, avatar_path} ->
      execute(
        "UPDATE agents SET avatar_path = '#{avatar_path}', updated_at = CURRENT_TIMESTAMP WHERE name = '#{name}'"
      )
    end)
  end

  def down do
    tool_names = Enum.map(@tools, fn {name, _module_name} -> name end)
    repo().delete_all(from_tool_name_in(tool_names))
  end

  defp from_tool_name_in(names) do
    import Ecto.Query
    from(t in "tools", where: t.name in ^names)
  end
end
