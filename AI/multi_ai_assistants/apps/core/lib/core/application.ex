defmodule Core.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    # 로케일에 따라 Latin-1로 시작하면 한글 로그가 \x{...}로 이스케이프됩니다.
    :ok = :io.setopts(:standard_io, encoding: :unicode)
    :ok = :io.setopts(:standard_error, encoding: :unicode)

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
