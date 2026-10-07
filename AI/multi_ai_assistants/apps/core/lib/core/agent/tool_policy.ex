defmodule Core.Agent.ToolPolicy do
  @moduledoc "Server-side policy for tools that change state or run commands."

  @restricted ~w(execute_code mcp_desktop_commander_call mcp_filesystem_call write_file)

  def restricted?(name), do: name in @restricted

  def authorize(name, opts) when is_binary(name) and is_list(opts) do
    allowed = Keyword.get(opts, :allowed_tools)

    cond do
      is_list(allowed) and name not in allowed -> {:error, :tool_not_allowed_for_agent}
      restricted?(name) -> {:error, :tool_requires_approval}
      true -> :ok
    end
  end

  def authorize(_, _), do: {:error, :invalid_tool_request}
end
