defmodule AgenticAiAgent.MCP do
  @moduledoc """
  Supervised collection of MCP clients. Reads server definitions from
  application config and spawns one `MCP.Client` per server. Servers can
  also be added/removed at runtime.

  Configure servers in `config/runtime.exs`:

      config :agentic_ai_agent, :mcp_servers, [
        %{
          name: "filesystem",
          command: "npx",
          args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"],
          env: %{},
          risk_level: :medium
        }
      ]
  """

  use Supervisor

  alias AgenticAiAgent.MCP.Client

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
    for cfg <- Application.get_env(:agentic_ai_agent, :mcp_servers, []) do
      launch(cfg)
    end
  end

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
