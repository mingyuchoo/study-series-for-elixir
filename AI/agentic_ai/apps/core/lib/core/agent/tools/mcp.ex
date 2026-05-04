defmodule Core.Agent.Tools.Mcp do
  @moduledoc """
  DB에 등록된 외부 MCP 서버를 stdio JSON-RPC로 호출하는 도구입니다.
  """

  @behaviour Core.Agent.Tool

  alias Core.Contexts.Mcps

  @timeout 30_000
  @protocol_version "2024-11-05"

  def definition("mcp_filesystem_call") do
    %{
      name: "mcp_filesystem_call",
      description:
        "Call a tool on the filesystem MCP server. Common tool names include read_file, read_multiple_files, list_directory, directory_tree, search_files, get_file_info, and list_allowed_directories. Use only paths allowed by MCP_FILESYSTEM_ROOT.",
      parameters:
        call_parameters("filesystem MCP tool name", "Arguments for the filesystem MCP tool")
    }
  end

  def definition("mcp_desktop_commander_call") do
    %{
      name: "mcp_desktop_commander_call",
      description:
        "Call a tool on the desktop-commander MCP server. Common tool names include execute_command, read_output, force_terminate, list_sessions, list_processes, kill_process, read_file, write_file, edit_block, list_directory, search_files, and get_file_info. Use only when local filesystem or terminal access is explicitly needed.",
      parameters:
        call_parameters(
          "desktop-commander MCP tool name",
          "Arguments for the desktop-commander MCP tool"
        )
    }
  end

  def definition(_), do: nil

  defp call_parameters(tool_description, arguments_description) do
    %{
      type: "object",
      properties: %{
        tool: %{
          type: "string",
          description: tool_description
        },
        arguments: %{
          type: "object",
          description: arguments_description,
          additionalProperties: true
        }
      },
      required: ["tool", "arguments"]
    }
  end

  def execute("mcp_filesystem_call", %{"tool" => tool, "arguments" => arguments})
      when is_binary(tool) and is_map(arguments) do
    call("filesystem", tool, arguments)
  end

  def execute("mcp_desktop_commander_call", %{"tool" => tool, "arguments" => arguments})
      when is_binary(tool) and is_map(arguments) do
    call("desktop-commander", tool, arguments)
  end

  def execute(_name, _args), do: {:error, "MCP tool call requires tool and arguments"}

  defp call(server_name, tool_name, arguments) do
    with {:ok, mcp} <- fetch_enabled_mcp(server_name),
         {:ok, command} <- resolve_command(mcp.command),
         {:ok, args} <- resolve_placeholders(mcp.args || []),
         {:ok, env} <- resolve_env(mcp.env || %{}),
         {:ok, port} <- open_port(command, args, env),
         :ok <- initialize(port),
         {:ok, result} <- call_tool(port, tool_name, arguments) do
      close_port(port)
      {:ok, normalize_result(result)}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_enabled_mcp(server_name) do
    case Mcps.get_mcp_by_name(server_name) do
      nil -> {:error, "MCP server not registered: #{server_name}"}
      %{enabled: false} -> {:error, "MCP server is disabled: #{server_name}"}
      mcp -> {:ok, mcp}
    end
  end

  defp resolve_command(command) when is_binary(command) do
    command = String.trim(command)

    cond do
      command == "" ->
        {:error, "MCP command is empty"}

      Path.type(command) == :absolute and File.exists?(command) ->
        {:ok, command}

      executable = System.find_executable(command) ->
        {:ok, executable}

      true ->
        {:error, "MCP command not found: #{command}"}
    end
  end

  defp resolve_command(_), do: {:error, "MCP command is invalid"}

  defp resolve_placeholders(values) when is_list(values) do
    case Enum.reduce_while(values, {:ok, []}, &resolve_placeholder_item/2) do
      {:ok, resolved} -> {:ok, Enum.reverse(resolved)}
      {:error, _} = error -> error
    end
  end

  defp resolve_env(env) when is_map(env) do
    case Enum.reduce_while(env, {:ok, []}, fn {key, value}, {:ok, acc} ->
           case resolve_placeholder(value) do
             {:ok, resolved} -> {:cont, {:ok, [{to_charlist(key), to_charlist(resolved)} | acc]}}
             {:error, _} = error -> {:halt, error}
           end
         end) do
      {:ok, resolved} -> {:ok, Enum.reverse(resolved)}
      {:error, _} = error -> error
    end
  end

  defp resolve_placeholder_item(value, {:ok, acc}) do
    case resolve_placeholder(value) do
      {:ok, resolved} -> {:cont, {:ok, [resolved | acc]}}
      {:error, _} = error -> {:halt, error}
    end
  end

  defp resolve_placeholder(value) when is_binary(value) do
    case Regex.run(~r/^\$\{([^}]+)\}$/, value) do
      [_, var] ->
        case System.get_env(var) || fallback_env(var) do
          nil -> {:error, "Required MCP environment variable is missing: #{var}"}
          "" -> {:error, "Required MCP environment variable is empty: #{var}"}
          resolved -> {:ok, resolved}
        end

      _ ->
        {:ok, value}
    end
  end

  defp resolve_placeholder(value), do: {:ok, to_string(value)}

  defp fallback_env("MCP_FILESYSTEM_ROOT"), do: System.get_env("HOME") || File.cwd!()
  defp fallback_env(_var), do: nil

  defp open_port(command, args, env) do
    port =
      Port.open({:spawn_executable, command}, [
        :binary,
        :exit_status,
        {:args, args},
        {:env, env}
      ])

    {:ok, port}
  rescue
    exception -> {:error, Exception.message(exception)}
  end

  defp initialize(port) do
    request(port, 1, "initialize", %{
      protocolVersion: @protocol_version,
      capabilities: %{},
      clientInfo: %{name: "agentic-ai", version: "0.1.0"}
    })
    |> case do
      {:ok, _} ->
        notify(port, "notifications/initialized", %{})
        :ok

      {:error, _} = error ->
        error
    end
  end

  defp call_tool(port, tool_name, arguments) do
    request(port, 2, "tools/call", %{name: tool_name, arguments: arguments})
  end

  defp request(port, id, method, params) do
    payload =
      Jason.encode!(%{
        jsonrpc: "2.0",
        id: id,
        method: method,
        params: params
      })

    Port.command(port, payload <> "\n")
    await_response(port, id, @timeout)
  end

  defp notify(port, method, params) do
    payload = Jason.encode!(%{jsonrpc: "2.0", method: method, params: params})
    Port.command(port, payload <> "\n")
  end

  defp await_response(port, id, timeout, buffer \\ "") do
    receive do
      {^port, {:data, data}} when is_binary(data) ->
        buffer = buffer <> data
        {lines, rest} = split_complete_lines(buffer)

        case find_response(lines, id) do
          {:ok, result} ->
            {:ok, result}

          {:error, reason} ->
            {:error, reason}

          :not_found ->
            await_response(port, id, timeout, rest)
        end

      {^port, {:exit_status, status}} ->
        {:error, "MCP process exited with status #{status}"}
    after
      timeout ->
        close_port(port)
        {:error, "MCP request timed out"}
    end
  end

  defp split_complete_lines(buffer) do
    parts = String.split(buffer, "\n")

    if String.ends_with?(buffer, "\n") do
      {Enum.reject(parts, &(&1 == "")), ""}
    else
      {parts |> Enum.drop(-1) |> Enum.reject(&(&1 == "")), List.last(parts) || ""}
    end
  end

  defp find_response(lines, id) do
    Enum.reduce_while(lines, :not_found, fn line, _acc ->
      case Jason.decode(String.trim(line)) do
        {:ok, %{"id" => ^id, "result" => result}} ->
          {:halt, {:ok, result}}

        {:ok, %{"id" => ^id, "error" => error}} ->
          {:halt, {:error, inspect(error)}}

        _ ->
          {:cont, :not_found}
      end
    end)
  end

  defp normalize_result(%{"content" => content} = result) when is_list(content) do
    text =
      content
      |> Enum.map(fn
        %{"type" => "text", "text" => text} -> sanitize_tool_text(text)
        other -> Jason.encode!(other)
      end)
      |> Enum.join("\n")

    result
    |> Map.put("content", sanitize_content(content))
    |> Map.put("text", text)
  end

  defp normalize_result(result), do: result

  defp sanitize_content(content) do
    Enum.map(content, fn
      %{"type" => "text", "text" => text} = item -> %{item | "text" => sanitize_tool_text(text)}
      item -> item
    end)
  end

  defp sanitize_tool_text(text) when is_binary(text) do
    text
    |> String.split("\n\n[SYSTEM INSTRUCTION]", parts: 2)
    |> hd()
  end

  defp sanitize_tool_text(text), do: text

  defp close_port(port) when is_port(port) do
    Port.close(port)
  rescue
    _ -> :ok
  end
end
