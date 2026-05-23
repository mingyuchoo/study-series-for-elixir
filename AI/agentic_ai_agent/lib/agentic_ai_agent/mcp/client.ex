defmodule AgenticAiAgent.MCP.Client do
  @moduledoc """
  Minimal MCP (Model Context Protocol) client over stdio.

  An MCP server is launched as a child OS process; the client sends
  newline-delimited JSON-RPC messages on its stdin and reads its stdout
  the same way. Once connected we run the standard handshake:

      → initialize
      ← initialize result
      → notifications/initialized
      → tools/list
      ← tools

  and register every discovered tool under the name `mcp__<server>__<tool>`
  with `AgenticAiAgent.Tools.Registry`. The registry's dispatch closure
  calls back into this GenServer with `tools/call`.

  Configuration:

      config :agentic_ai_agent, :mcp_servers, [
        %{name: "filesystem",
          command: "npx",
          args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"],
          env: %{},
          risk_level: :medium}
      ]

  Only stdio transport is supported in this phase; HTTP+SSE is future work.
  """

  use GenServer
  require Logger

  alias AgenticAiAgent.Tools.Registry, as: ToolRegistry
  alias AgenticAiAgent.Tools.Registry.DynamicEntry

  @protocol_version "2024-11-05"
  @default_timeout_ms 15_000
  @prefix "mcp"

  # ----- Client -----

  def start_link(server_cfg) do
    GenServer.start_link(__MODULE__, server_cfg, name: via(server_cfg.name))
  end

  def via(server_name), do: {:via, Registry, {AgenticAiAgent.MCP.Registry, server_name}}

  @doc "Returns `{:ok, %{name, tools: [...], status: ...}}` or `:error`."
  def info(server_name), do: GenServer.call(via(server_name), :info)

  @doc "Call a tool on this server by its *local* name (no prefix)."
  def call_tool(server_name, tool_name, args, timeout \\ @default_timeout_ms),
    do: GenServer.call(via(server_name), {:call_tool, tool_name, args}, timeout + 1_000)

  @doc "List active MCP servers known to the supervisor / registry."
  def list_servers do
    Registry.select(AgenticAiAgent.MCP.Registry, [{{:"$1", :_, :_}, [], [:"$1"]}])
    |> Enum.sort()
  end

  # ----- Server -----

  defmodule State do
    @moduledoc false
    defstruct [
      :server_name,
      :command,
      :args,
      :env,
      :risk_level,
      :port,
      :buffer,
      :next_id,
      :pending,
      :tools,
      :status,
      :error
    ]
  end

  @impl true
  def init(cfg) do
    state = %State{
      server_name: cfg.name,
      command: cfg.command,
      args: Map.get(cfg, :args, []),
      env: Map.get(cfg, :env, %{}),
      risk_level: Map.get(cfg, :risk_level, :medium),
      buffer: "",
      next_id: 1,
      pending: %{},
      tools: [],
      status: :starting
    }

    case open_port(state) do
      {:ok, port} ->
        Process.send_after(self(), :handshake, 50)
        {:ok, %{state | port: port}}

      {:error, reason} ->
        Logger.warning("MCP[#{state.server_name}] failed to start: #{inspect(reason)}")
        {:ok, %{state | status: :failed, error: inspect(reason)}}
    end
  end

  @impl true
  def handle_info(:handshake, state) do
    state = send_request(state, "initialize", %{
      "protocolVersion" => @protocol_version,
      "clientInfo" => %{"name" => "agentic_ai_agent", "version" => "0.1.0"},
      "capabilities" => %{}
    })

    {:noreply, %{state | status: :initializing}}
  end

  def handle_info({port, {:data, chunk}}, %{port: port} = state) do
    {state, lines} = buffer_lines(state, chunk)
    state = Enum.reduce(lines, state, &handle_line/2)
    {:noreply, state}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.warning("MCP[#{state.server_name}] exited with status #{status}")
    # Unregister all tools we owned.
    for t <- state.tools, do: ToolRegistry.unregister(qualified_name(state.server_name, t["name"]))
    {:noreply, %{state | port: nil, status: :exited}}
  end

  def handle_info(_other, state), do: {:noreply, state}

  @impl true
  def handle_call(:info, _from, state) do
    {:reply,
     {:ok,
      %{
        name: state.server_name,
        status: state.status,
        error: state.error,
        tools: state.tools,
        risk_level: state.risk_level
      }}, state}
  end

  def handle_call({:call_tool, tool_name, args}, from, state) do
    if state.status != :ready do
      {:reply, {:error, "MCP server #{state.server_name} is #{state.status}"}, state}
    else
      state = send_request(state, "tools/call", %{"name" => tool_name, "arguments" => args || %{}}, from)
      {:noreply, state}
    end
  end

  @impl true
  def terminate(_reason, %{port: port} = _state) when not is_nil(port) do
    try do
      Port.close(port)
    catch
      :error, _ -> :ok
    end

    :ok
  end

  def terminate(_reason, _state), do: :ok

  # ----- Line buffering -----

  defp buffer_lines(state, chunk) do
    data = state.buffer <> chunk

    case String.split(data, "\n") do
      [] -> {%{state | buffer: ""}, []}
      [partial] -> {%{state | buffer: partial}, []}
      lines ->
        {complete, [partial]} = Enum.split(lines, length(lines) - 1)
        {%{state | buffer: partial}, complete}
    end
  end

  defp handle_line("", state), do: state

  defp handle_line(line, state) do
    case Jason.decode(line) do
      {:ok, %{"id" => id} = msg} when is_map_key(msg, "result") or is_map_key(msg, "error") ->
        on_response(id, msg, state)

      {:ok, %{"method" => method} = msg} ->
        on_notification(method, msg, state)

      {:ok, _} ->
        state

      {:error, _} ->
        Logger.debug("MCP[#{state.server_name}] non-JSON line: #{inspect(line)}")
        state
    end
  end

  defp on_response(id, msg, state) do
    case Map.pop(state.pending, id) do
      {nil, _} ->
        state

      {{:call, method, from}, rest_pending} ->
        result = msg["result"]
        error = msg["error"]
        state = %{state | pending: rest_pending}
        handle_response(method, result, error, from, state)
    end
  end

  defp handle_response("initialize", _result, nil, _from, state) do
    # Send notifications/initialized, then ask for tools.
    state = send_notification(state, "notifications/initialized", %{})
    state = send_request(state, "tools/list", %{})
    %{state | status: :requesting_tools}
  end

  defp handle_response("tools/list", %{"tools" => tools}, nil, _from, state) do
    tools = tools || []
    register_tools(state.server_name, tools, state.risk_level)
    Logger.info("MCP[#{state.server_name}] ready with #{length(tools)} tool(s)")
    %{state | status: :ready, tools: tools}
  end

  defp handle_response("tools/call", result, nil, from, state) do
    GenServer.reply(from, {:ok, result})
    state
  end

  defp handle_response(_method, _result, %{"message" => msg}, from, state) do
    if from, do: GenServer.reply(from, {:error, msg})
    state
  end

  defp handle_response(method, _result, error, from, state) do
    if from, do: GenServer.reply(from, {:error, error})
    Logger.warning("MCP[#{state.server_name}] #{method} returned: #{inspect(error)}")
    state
  end

  defp on_notification(_method, _msg, state), do: state

  # ----- Sending -----

  defp send_request(state, method, params, from \\ nil) do
    id = state.next_id

    payload =
      %{"jsonrpc" => "2.0", "id" => id, "method" => method, "params" => params}
      |> Jason.encode!()

    Port.command(state.port, payload <> "\n")

    %{
      state
      | next_id: id + 1,
        pending: Map.put(state.pending, id, {:call, method, from})
    }
  end

  defp send_notification(state, method, params) do
    payload =
      %{"jsonrpc" => "2.0", "method" => method, "params" => params}
      |> Jason.encode!()

    Port.command(state.port, payload <> "\n")
    state
  end

  # ----- Port -----

  defp open_port(state) do
    case System.find_executable(state.command) do
      nil ->
        {:error, {:command_not_found, state.command}}

      exec ->
        env =
          state.env
          |> Enum.map(fn {k, v} -> {String.to_charlist(to_string(k)), String.to_charlist(to_string(v))} end)

        port =
          Port.open({:spawn_executable, exec},
            [:binary, :exit_status, :use_stdio, :stderr_to_stdout, args: state.args, env: env]
          )

        {:ok, port}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  # ----- Tool registration -----

  defp register_tools(server_name, tools, risk_level) do
    for t <- tools do
      qname = qualified_name(server_name, t["name"])

      entry = %DynamicEntry{
        name: qname,
        description: Map.get(t, "description", "MCP tool from #{server_name}"),
        input_schema: Map.get(t, "inputSchema", %{"type" => "object"}),
        output_schema: %{"type" => "object"},
        risk_level: risk_level,
        source: {:mcp, server_name, t["name"]},
        dispatch: fn args ->
          case call_tool(server_name, t["name"], args) do
            {:ok, result} ->
              {:ok, normalize_tool_result(result)}

            {:error, reason} ->
              {:error, reason}
          end
        end
      }

      ToolRegistry.register(entry)
    end
  end

  defp qualified_name(server, tool), do: "#{@prefix}__#{server}__#{tool}"

  # MCP tools/call returns %{"content" => [%{"type" => "text", "text" => ...}, ...], "isError" => false}
  defp normalize_tool_result(%{"content" => content} = result) when is_list(content) do
    text =
      content
      |> Enum.filter(&match?(%{"type" => "text"}, &1))
      |> Enum.map_join("\n", &Map.get(&1, "text", ""))

    %{"text" => text, "raw" => result}
  end

  defp normalize_tool_result(result) when is_map(result), do: result
  defp normalize_tool_result(other), do: %{"value" => other}
end
