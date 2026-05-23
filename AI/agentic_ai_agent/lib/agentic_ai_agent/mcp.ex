defmodule AgenticAiAgent.MCP do
  @moduledoc """
  Supervised collection of MCP clients.

  Server configuration is persisted in the `mcp_servers` table and managed
  by `AgenticAiAgent.MCP.Servers` (CRUD + lifecycle). On boot every enabled
  row is launched under `AgenticAiAgent.MCP.ClientSupervisor`; subsequent
  add/edit/delete via the LiveView reconciles the supervisor tree.

  An optional bootstrap list under `:mcp_servers` in `config/runtime.exs`
  is seeded into the table on first boot (when the table is empty) and
  ignored afterwards. This preserves the previous config-driven workflow
  for fresh installs without competing with DB edits.
  """

  use Supervisor
  require Logger

  alias AgenticAiAgent.MCP.{Client, Server, Servers}

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {Registry, keys: :unique, name: AgenticAiAgent.MCP.Registry},
      {DynamicSupervisor, name: AgenticAiAgent.MCP.ClientSupervisor, strategy: :one_for_one},
      {Task, fn -> launch_configured_servers() end}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  defp launch_configured_servers do
    maybe_seed_from_app_env()

    for %Server{} = row <- Servers.list_records(), row.enabled do
      Servers.start_one(row)
    end
  end

  # If the table is empty AND legacy `:mcp_servers` config exists, seed the
  # table from it. After that, the DB is authoritative.
  defp maybe_seed_from_app_env do
    legacy = Application.get_env(:agentic_ai_agent, :mcp_servers, [])

    cond do
      legacy == [] ->
        :ok

      Servers.list_records() != [] ->
        :ok

      true ->
        Logger.info("MCP: seeding mcp_servers table from :mcp_servers app env (#{length(legacy)} entries)")

        for cfg <- legacy do
          attrs = %{
            "name" => to_string(cfg[:name] || cfg["name"]),
            "command" => to_string(cfg[:command] || cfg["command"] || ""),
            "args" => cfg[:args] || cfg["args"] || [],
            "env" => stringify_env(cfg[:env] || cfg["env"] || %{}),
            "risk_level" => to_string(cfg[:risk_level] || cfg["risk_level"] || "medium"),
            "enabled" => true
          }

          case Servers.create(attrs) do
            {:ok, _} -> :ok
            {:error, cs} -> Logger.warning("MCP seed skipped #{inspect(attrs["name"])}: #{inspect(cs.errors)}")
          end
        end
    end
  rescue
    e ->
      Logger.warning("MCP seed-from-env failed: #{Exception.message(e)} — continuing with empty config")
      :ok
  end

  defp stringify_env(env) when is_map(env) do
    Map.new(env, fn {k, v} -> {to_string(k), to_string(v)} end)
  end

  defp stringify_env(_), do: %{}

  @doc "Launch a new MCP server under supervision."
  def launch(%{name: _name} = cfg) do
    DynamicSupervisor.start_child(AgenticAiAgent.MCP.ClientSupervisor, {Client, cfg})
  end

  @doc "List server names known to the registry."
  def list_servers, do: Client.list_servers()

  @doc "Get info about a single server."
  def info(name), do: Client.info(name)

  @doc "Summary of every running server (name, status, tool count)."
  def status do
    for name <- list_servers() do
      case info(name) do
        {:ok, info} ->
          %{name: name, status: info.status, tool_count: length(info.tools), error: info.error}

        _ ->
          %{name: name, status: :unknown, tool_count: 0, error: nil}
      end
    end
  end
end
