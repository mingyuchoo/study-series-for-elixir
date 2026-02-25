defmodule Core.Application do
  @moduledoc false
  use Application

  require Logger

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
    result = Supervisor.start_link(children, opts)

    # Repo가 시작된 후 에이전트 설정을 DB에 동기화
    case Core.Agent.ConfigLoader.load_all_configs() do
      {:ok, agents} ->
        Logger.info("에이전트 설정 로드 완료: #{length(agents)}개")

      {:error, reason} ->
        Logger.warning("에이전트 설정 로드 실패: #{inspect(reason)}")
    end

    result
  end
end
