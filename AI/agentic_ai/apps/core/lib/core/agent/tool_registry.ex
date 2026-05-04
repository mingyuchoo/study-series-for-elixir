defmodule Core.Agent.ToolRegistry do
  @moduledoc """
  에이전트가 사용할 수 있는 도구들의 레지스트리.
  도구들은 OpenAI 함수 호출 명세를 따릅니다.
  """

  import Ecto.Query

  alias Core.Repo
  alias Core.Schema.Tool

  @doc """
  정의와 함께 사용 가능한 모든 도구를 가져옵니다.
  """
  def get_tools do
    Tool
    |> where([t], t.enabled == true)
    |> order_by([t], asc: t.name)
    |> Repo.all()
    |> Enum.map(fn tool ->
      with {:ok, module} <- fetch_tool_module(tool) do
        module.definition(tool.name)
      else
        _ -> nil
      end
    end)
    |> Enum.filter(& &1)
  end

  @doc """
  이름으로 도구를 실행하고 주어진 인자를 전달합니다.
  """
  def execute(tool_name, arguments) do
    case Repo.get_by(Tool, name: tool_name, enabled: true) do
      nil ->
        {:error, :tool_not_found}

      tool ->
        with {:ok, module} <- fetch_tool_module(tool) do
          try do
            module.execute(tool_name, arguments)
          rescue
            e -> {:error, Exception.message(e)}
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

  defp fetch_tool_module(%Tool{module_name: module_name}) when is_binary(module_name) do
    module =
      module_name
      |> String.trim_leading("Elixir.")
      |> String.split(".")
      |> Module.safe_concat()

    if Code.ensure_loaded?(module) and function_exported?(module, :definition, 1) and
         function_exported?(module, :execute, 2) do
      {:ok, module}
    else
      {:error, :invalid_tool_module}
    end
  rescue
    ArgumentError -> {:error, :invalid_tool_module}
  end

  defp fetch_tool_module(_tool), do: {:error, :invalid_tool_module}
end
