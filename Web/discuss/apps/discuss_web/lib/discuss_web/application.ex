defmodule DiscussWeb.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        DiscussWeb.Telemetry,
        DiscussWeb.Endpoint
      ] ++
        if Mix.env() != :test do
          [Supervisor.child_spec({Task, &DiscussAuth.Seeder.run/0}, restart: :temporary)]
        else
          []
        end

    opts = [strategy: :one_for_one, name: DiscussWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    DiscussWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
