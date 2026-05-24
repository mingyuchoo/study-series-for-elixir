defmodule AgenticAiAgent.MCP.Servers do
  @moduledoc """
  CRUD + lifecycle for `AgenticAiAgent.MCP.Server` rows.

  This is the authoritative source for which MCP servers exist. The
  supervisor in `AgenticAiAgent.MCP` consults `list_records/0` at boot and
  this module on every CRUD operation to keep the running supervisor tree
  in sync with the database.

  Lifecycle helpers:

    * `start_one/1` — launch the supervisor child for a row (if enabled and
      not already running). Idempotent.
    * `stop_one/1` — terminate the supervisor child for a server name (if
      running). Idempotent. Tools auto-unregister via the client's exit
      handler.
    * `restart_one/1` — stop then start.

  CRUD wrappers (`create/1`, `update/2`, `delete/1`) keep the running tree
  in sync automatically.
  """

  import Ecto.Query
  require Logger

  alias AgenticAiAgent.Repo
  alias AgenticAiAgent.MCP
  alias AgenticAiAgent.MCP.Server

  @supervisor AgenticAiAgent.MCP.ClientSupervisor
  @registry AgenticAiAgent.MCP.Registry

  # ----- Read -----

  @spec list_records() :: [Server.t()]
  def list_records do
    Repo.all(from s in Server, order_by: [asc: s.name])
  rescue
    e ->
      Logger.warning("MCP.Servers.list_records/0: #{Exception.message(e)} — returning []")
      []
  end

  @spec get!(binary()) :: Server.t()
  def get!(id), do: Repo.get!(Server, id)

  @spec get_by_name(String.t()) :: Server.t() | nil
  def get_by_name(name), do: Repo.get_by(Server, name: name)

  @spec change(Server.t(), map()) :: Ecto.Changeset.t()
  def change(%Server{} = server, attrs \\ %{}), do: Server.changeset(server, attrs)

  # ----- Write -----

  @spec create(map()) :: {:ok, Server.t()} | {:error, Ecto.Changeset.t()}
  def create(attrs) do
    %Server{}
    |> Server.changeset(attrs)
    |> Repo.insert()
    |> tap_sync(:start)
  end

  @spec update(Server.t(), map()) :: {:ok, Server.t()} | {:error, Ecto.Changeset.t()}
  def update(%Server{} = server, attrs) do
    old_name = server.name

    server
    |> Server.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated} = ok ->
        # Always stop the old name (it may have changed) then start the new row.
        stop_one(old_name)
        if updated.enabled, do: start_one(updated)
        ok

      err ->
        err
    end
  end

  @spec delete(Server.t()) :: {:ok, Server.t()} | {:error, Ecto.Changeset.t()}
  def delete(%Server{} = server) do
    stop_one(server.name)
    Repo.delete(server)
  end

  # ----- Lifecycle -----

  @doc "Launch a server child. Idempotent: returns :ok if already running."
  @spec start_one(Server.t()) :: :ok | {:error, term()}
  def start_one(%Server{enabled: false}), do: :ok

  def start_one(%Server{} = server) do
    cfg = %{
      name: server.name,
      transport: server.transport,
      risk_level: String.to_existing_atom(server.risk_level),
      # stdio
      command: server.command,
      args: Server.args_list(server),
      env: Server.env_map(server),
      # http_sse
      url: server.url,
      headers: Server.headers_map(server)
    }

    case MCP.launch(cfg) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} ->
        Logger.warning("MCP start_one(#{server.name}) failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc "Stop a running server child by name. Idempotent."
  @spec stop_one(String.t()) :: :ok
  def stop_one(name) when is_binary(name) do
    case Registry.lookup(@registry, name) do
      [{pid, _}] ->
        _ = DynamicSupervisor.terminate_child(@supervisor, pid)
        :ok

      [] ->
        :ok
    end
  rescue
    _ -> :ok
  end

  @doc "Stop then start a server by record."
  @spec restart_one(Server.t()) :: :ok | {:error, term()}
  def restart_one(%Server{} = server) do
    stop_one(server.name)
    start_one(server)
  end

  # ----- Internals -----

  defp tap_sync({:ok, %Server{} = server} = ok, :start) do
    if server.enabled, do: start_one(server)
    ok
  end

  defp tap_sync(other, _), do: other
end
