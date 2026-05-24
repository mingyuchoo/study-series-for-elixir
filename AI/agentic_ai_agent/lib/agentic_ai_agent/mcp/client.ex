defmodule AgenticAiAgent.MCP.Client do
  @moduledoc """
  Minimal MCP (Model Context Protocol) client supporting two transports.

  * **stdio** — launches the server as a child OS process and exchanges
    newline-delimited JSON-RPC messages on stdin/stdout.
  * **http_sse** — opens a long-lived `GET` to the server's SSE endpoint;
    the first SSE event (`event: endpoint`) carries the POST URL where
    client→server JSON-RPC messages are sent. Server→client responses and
    notifications arrive as further SSE events (`event: message`).

  Either transport runs the same handshake:

      → initialize
      ← initialize result
      → notifications/initialized
      → tools/list
      ← tools

  and registers every discovered tool as `mcp__<server>__<tool>` with
  `AgenticAiAgent.Tools.Registry`. The registry's dispatch closure calls
  back into this GenServer with `tools/call`.

  The transport is chosen per-row in the `mcp_servers` table; see
  `AgenticAiAgent.MCP.Server` for the schema.
  """

  use GenServer
  require Logger

  alias AgenticAiAgent.Tools.Registry, as: ToolRegistry
  alias AgenticAiAgent.Tools.Registry.DynamicEntry

  @protocol_version "2024-11-05"
  @default_timeout_ms 15_000
  @prefix "mcp"

  # Exponential backoff schedule for auto-reconnect after a transport drop.
  # The Nth retry waits at the Nth (capped) entry; further retries reuse the
  # last value indefinitely.
  @reconnect_backoff_ms [1_000, 2_000, 4_000, 8_000, 16_000, 30_000]

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
      :transport,
      :risk_level,
      # stdio
      :command,
      :args,
      :env,
      :port,
      # http_sse
      :url,
      :headers,
      :post_url,
      :sse_task,
      # shared
      :buffer,
      :next_id,
      :pending,
      :tools,
      :status,
      :error,
      reconnect_attempts: 0
    ]
  end

  @impl true
  def init(cfg) do
    transport = to_string(Map.get(cfg, :transport, "stdio"))

    state = %State{
      server_name: cfg.name,
      transport: transport,
      risk_level: Map.get(cfg, :risk_level, :medium),
      command: Map.get(cfg, :command),
      args: Map.get(cfg, :args, []),
      env: Map.get(cfg, :env, %{}),
      url: Map.get(cfg, :url),
      headers: Map.get(cfg, :headers, %{}),
      buffer: "",
      next_id: 1,
      pending: %{},
      tools: [],
      status: :starting
    }

    case start_transport(state) do
      {:ok, state} -> {:ok, state}
      {:error, reason} ->
        Logger.warning("MCP[#{state.server_name}] failed to start: #{inspect(reason)}")
        {:ok, %{state | status: :failed, error: inspect(reason)}}
    end
  end

  defp start_transport(%{transport: "stdio"} = state) do
    case open_port(state) do
      {:ok, port} ->
        # stdio transport is ready to handshake as soon as the port is open.
        Process.send_after(self(), :handshake, 50)
        {:ok, %{state | port: port}}

      err ->
        err
    end
  end

  defp start_transport(%{transport: "http_sse"} = state) do
    # HTTP+SSE: spawn a linked Task that streams the SSE endpoint. Handshake
    # waits for the first {:sse_event, "endpoint", post_url} message before
    # any JSON-RPC is sent. Task.start_link only ever returns {:ok, pid} —
    # transport failures surface later as {:sse_done, reason}.
    {:ok, pid} = start_sse_task(state)
    {:ok, %{state | sse_task: pid, status: :connecting}}
  end

  defp start_transport(%{transport: other}),
    do: {:error, {:unknown_transport, other}}

  @impl true
  def handle_info(:handshake, state) do
    state = send_request(state, "initialize", %{
      "protocolVersion" => @protocol_version,
      "clientInfo" => %{"name" => "agentic_ai_agent", "version" => "0.1.0"},
      "capabilities" => %{}
    })

    {:noreply, %{state | status: :initializing}}
  end

  def handle_info({port, {:data, chunk}}, %{port: port} = state) when not is_nil(port) do
    {state, lines} = buffer_lines(state, chunk)
    state = Enum.reduce(lines, state, &handle_line/2)
    {:noreply, state}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) when not is_nil(port) do
    Logger.warning("MCP[#{state.server_name}] exited with status #{status}")
    state = drop_tools(state)
    state = %{state | port: nil, status: :exited, error: "exit_status #{status}"}
    {:noreply, schedule_reconnect(state)}
  end

  # ----- HTTP+SSE messages from the streaming task -----

  # The very first SSE event is "endpoint" carrying the POST URL for
  # client→server JSON-RPC messages.
  def handle_info({:sse_event, "endpoint", post_url}, %{transport: "http_sse"} = state) do
    post_url = String.trim(post_url) |> absolutize(state.url)
    Process.send_after(self(), :handshake, 0)
    {:noreply, %{state | post_url: post_url, status: :initializing}}
  end

  # Every other JSON-RPC frame arrives as a "message" event.
  def handle_info({:sse_event, "message", data}, %{transport: "http_sse"} = state) do
    {:noreply, handle_line(data, state)}
  end

  # Servers may include keepalive comments or unknown events — ignore.
  def handle_info({:sse_event, _other, _data}, state), do: {:noreply, state}

  def handle_info({:sse_done, reason}, %{transport: "http_sse"} = state) do
    Logger.warning("MCP[#{state.server_name}] SSE stream ended: #{inspect(reason)}")
    state = drop_tools(state)
    state = %{state | sse_task: nil, post_url: nil, status: :exited, error: inspect(reason)}
    {:noreply, schedule_reconnect(state)}
  end

  # Auto-reconnect tick — try start_transport again with a fresh buffer/pending.
  def handle_info(:reconnect, state) do
    state = %{state | buffer: "", pending: %{}, status: :reconnecting}

    case start_transport(state) do
      {:ok, state} ->
        {:noreply, state}

      {:error, reason} ->
        Logger.warning("MCP[#{state.server_name}] reconnect failed: #{inspect(reason)}")
        {:noreply, schedule_reconnect(%{state | status: :exited, error: inspect(reason)})}
    end
  end

  def handle_info(_other, state), do: {:noreply, state}

  defp drop_tools(state) do
    for t <- state.tools, do: ToolRegistry.unregister(qualified_name(state.server_name, t["name"]))
    %{state | tools: []}
  end

  defp schedule_reconnect(state) do
    n = state.reconnect_attempts
    delay = Enum.at(@reconnect_backoff_ms, n, List.last(@reconnect_backoff_ms))
    Process.send_after(self(), :reconnect, delay)

    Logger.info(
      "MCP[#{state.server_name}] will reconnect in #{delay}ms (attempt #{n + 1})"
    )

    %{state | reconnect_attempts: n + 1}
  end

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
  def terminate(_reason, %{transport: "stdio", port: port}) when not is_nil(port) do
    try do
      Port.close(port)
    catch
      :error, _ -> :ok
    end

    :ok
  end

  def terminate(_reason, %{transport: "http_sse", sse_task: pid}) when is_pid(pid) do
    # The SSE Task is linked to us; it will be torn down by the link, but
    # we also send an explicit shutdown to short-circuit the receive loop.
    Process.exit(pid, :shutdown)
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
    # Successful handshake — reset the reconnect counter so a future drop
    # starts the backoff schedule from the top again.
    %{state | status: :ready, tools: tools, reconnect_attempts: 0, error: nil}
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

    do_send(state, payload)

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

    do_send(state, payload)
    state
  end

  defp do_send(%{transport: "stdio", port: port}, payload) when not is_nil(port) do
    Port.command(port, payload <> "\n")
  end

  defp do_send(%{transport: "http_sse", post_url: url, headers: headers}, payload)
       when is_binary(url) do
    headers_list = headers_to_list(headers)
    body = payload

    # POST in a Task so the GenServer keeps draining SSE messages while the
    # HTTP roundtrip happens. The response is irrelevant — actual JSON-RPC
    # responses come via SSE.
    _ =
      Task.start(fn ->
        case Req.post(url,
               headers: headers_list,
               body: body,
               headers_extra: [{"content-type", "application/json"}],
               receive_timeout: 10_000
             ) do
          {:ok, %{status: status}} when status >= 200 and status < 300 -> :ok
          other -> Logger.warning("MCP HTTP POST failed: #{inspect(other)}")
        end
      end)

    :ok
  end

  defp do_send(_state, _payload), do: :ok

  # ----- HTTP+SSE streaming task -----

  defp start_sse_task(state) do
    parent = self()
    url = state.url
    headers = headers_to_list(state.headers)

    {:ok, _pid} =
      Task.start_link(fn -> sse_loop(parent, url, headers) end)
  end

  defp sse_loop(parent, url, headers) do
    headers = [{"accept", "text/event-stream"} | headers]

    result =
      Req.get(url,
        headers: headers,
        receive_timeout: :infinity,
        retry: false,
        into: fn {:data, chunk}, {req, resp} ->
          buf = (resp.private[:sse_buf] || "") <> chunk
          {events, rest} = parse_sse_frames(buf)
          for {event, data} <- events, do: send(parent, {:sse_event, event, data})
          resp = update_in(resp.private[:sse_buf], fn _ -> rest end)
          {:cont, {req, resp}}
        end
      )

    reason =
      case result do
        {:ok, %{status: status}} when status >= 200 and status < 300 -> :closed
        {:ok, %{status: status}} -> {:http_error, status}
        {:error, err} -> {:transport, err}
      end

    send(parent, {:sse_done, reason})
  end

  # SSE frames are blocks of lines separated by a blank line. Each block may
  # contain "event:" (defaults to "message") and one or more "data:" lines
  # which are concatenated with newlines.
  defp parse_sse_frames(buffer) do
    parts = String.split(buffer, ~r/\r?\n\r?\n/)
    {complete, [partial]} = Enum.split(parts, length(parts) - 1)
    {Enum.map(complete, &parse_sse_frame/1), partial}
  end

  defp parse_sse_frame(block) do
    {event, data_lines} =
      block
      |> String.split(~r/\r?\n/)
      |> Enum.reduce({"message", []}, fn line, {ev, data} ->
        cond do
          String.starts_with?(line, ":") ->
            {ev, data}

          String.starts_with?(line, "event:") ->
            {String.trim(String.replace_prefix(line, "event:", "")), data}

          String.starts_with?(line, "data:") ->
            {ev, [String.trim(String.replace_prefix(line, "data:", "")) | data]}

          true ->
            {ev, data}
        end
      end)

    {event, data_lines |> Enum.reverse() |> Enum.join("\n")}
  end

  defp headers_to_list(headers) when is_map(headers),
    do: for({k, v} <- headers, do: {to_string(k), to_string(v)})

  defp headers_to_list(_), do: []

  # If the endpoint URL is relative, resolve it against the original SSE URL.
  defp absolutize(post, sse) do
    cond do
      String.starts_with?(post, "http://") or String.starts_with?(post, "https://") ->
        post

      String.starts_with?(post, "/") ->
        uri = URI.parse(sse)
        "#{uri.scheme}://#{uri.host}#{port_segment(uri)}#{post}"

      true ->
        # Same-directory relative — concatenate.
        Path.dirname(sse) <> "/" <> post
    end
  end

  defp port_segment(%URI{port: nil}), do: ""
  defp port_segment(%URI{scheme: "http", port: 80}), do: ""
  defp port_segment(%URI{scheme: "https", port: 443}), do: ""
  defp port_segment(%URI{port: p}), do: ":#{p}"

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
