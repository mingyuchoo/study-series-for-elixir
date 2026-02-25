defmodule Core.Agent.ToolRegistry do
  @moduledoc """
  에이전트가 사용할 수 있는 도구들의 레지스트리.
  도구들은 OpenAI 함수 호출 명세를 따릅니다.
  """

  alias Core.Agent.Tools

  @tools %{
    "get_current_time" => Tools.DateTime,
    "search_web" => Tools.WebSearch,
    "calculate" => Tools.Calculator,
    "read_file" => Tools.FileSystem,
    "write_file" => Tools.FileSystem,
    "list_directory" => Tools.FileSystem,
    "execute_code" => Tools.CodeExecutor,
    # Firecrawl MCP 도구들
    "firecrawl_scrape" => Tools.Firecrawl,
    "firecrawl_search" => Tools.Firecrawl
  }

  @doc """
  정의와 함께 사용 가능한 모든 도구를 가져옵니다.
  """
  def get_tools do
    @tools
    |> Enum.map(fn {name, module} ->
      apply(module, :definition, [name])
    end)
    |> Enum.filter(& &1)
  end

  @doc """
  이름으로 도구를 실행하고 주어진 인자를 전달합니다.
  """
  def execute(tool_name, arguments) do
    case Map.get(@tools, tool_name) do
      nil ->
        {:error, :tool_not_found}

      module ->
        try do
          apply(module, :execute, [tool_name, arguments])
        rescue
          e -> {:error, Exception.message(e)}
        end
    end
  end

  @doc """
  도구가 존재하는지 확인합니다.
  """
  def tool_exists?(tool_name) do
    Map.has_key?(@tools, tool_name)
  end
end
