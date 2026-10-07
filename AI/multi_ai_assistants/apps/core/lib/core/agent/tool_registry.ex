defmodule Core.Agent.ToolRegistry do
  @moduledoc """
  에이전트가 사용할 수 있는 도구들의 레지스트리.
  도구들은 OpenAI 함수 호출 명세를 따릅니다.
  """

  import Ecto.Query

  alias Core.Repo
  alias Core.Schema.Tool
  alias Core.Agent.ToolPolicy
  alias Core.Agent.Telemetry

  @tool_modules %{
    "calculate" => Core.Agent.Tools.Calculator,
    "execute_code" => Core.Agent.Tools.CodeExecutor,
    "firecrawl_scrape" => Core.Agent.Tools.Firecrawl,
    "firecrawl_search" => Core.Agent.Tools.Firecrawl,
    "get_current_time" => Core.Agent.Tools.DateTime,
    "list_directory" => Core.Agent.Tools.FileSystem,
    "mcp_desktop_commander_call" => Core.Agent.Tools.Mcp,
    "mcp_filesystem_call" => Core.Agent.Tools.Mcp,
    "read_file" => Core.Agent.Tools.FileSystem,
    "search_vector_rag" => Core.Agent.Tools.VectorRagSearch,
    "search_web" => Core.Agent.Tools.WebSearch,
    "write_file" => Core.Agent.Tools.FileSystem
  }

  @doc """
  정의와 함께 사용 가능한 모든 도구를 가져옵니다.
  """
  def get_tools do
    Tool
    |> where([t], t.enabled == true)
    |> order_by([t], asc: t.name)
    |> Repo.all()
    |> Enum.flat_map(fn tool ->
      if ToolPolicy.restricted?(tool.name) do
        []
      else
        case tool_module(tool.name) do
          {:ok, module} -> List.wrap(module.definition(tool.name))
          {:error, :invalid_tool_module} -> []
        end
      end
    end)
  end

  @doc """
  이름으로 도구를 실행하고 주어진 인자를 전달합니다.
  """
  def execute(tool_name, arguments, opts \\ []) do
    with :ok <- ToolPolicy.authorize(tool_name, opts) do
      Telemetry.measure(:tool, %{run_id: Keyword.get(opts, :run_id), tool: tool_name}, fn ->
        do_execute(tool_name, arguments, opts)
      end)
    end
  end

  defp do_execute(tool_name, arguments, opts) do
    case Repo.get_by(Tool, name: tool_name, enabled: true) do
      nil ->
        {:error, :tool_not_found}

      tool ->
        with {:ok, module} <- tool_module(tool.name) do
          if tool_name == "search_vector_rag" do
            Core.Agent.Tools.VectorRagSearch.execute(
              tool_name,
              arguments,
              Keyword.get(opts, :user_id)
            )
          else
            if tool_name in ~w(read_file write_file list_directory) do
              Core.Agent.Tools.FileSystem.execute(
                tool_name,
                arguments,
                Keyword.get(opts, :user_id)
              )
            else
              module.execute(tool_name, arguments)
            end
          end
        end
    end
  end

  @doc """
  도구가 존재하는지 확인합니다.
  """
  def tool_exists?(tool_name) do
    Repo.exists?(from(t in Tool, where: t.name == ^tool_name and t.enabled == true))
  end

  defp tool_module(tool_name) do
    case Map.fetch(@tool_modules, tool_name) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, :invalid_tool_module}
    end
  end
end
