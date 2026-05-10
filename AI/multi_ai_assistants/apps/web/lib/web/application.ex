defmodule Web.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      WebWeb.Telemetry,
      {Phoenix.PubSub, name: Web.PubSub},
      WebWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Web.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    WebWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
