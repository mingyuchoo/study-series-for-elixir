defmodule Discuss.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Discuss.Repo,
      {DNSCluster, query: Application.get_env(:discuss, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Discuss.PubSub},
      {Finch, name: Discuss.Finch}
    ]

    opts = [strategy: :one_for_one, name: Discuss.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
