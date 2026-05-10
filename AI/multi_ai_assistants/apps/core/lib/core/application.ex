defmodule Core.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Core.Repo,
      {Registry, keys: :unique, name: Core.Agent.Registry},
      {Core.Agent.SkillRegistry, []},
      {Core.Agent.Supervisor, []},
      # MCP 서버 (Model Context Protocol)
      {Core.MCP.Server, []}
    ]

    opts = [strategy: :one_for_one, name: Core.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
