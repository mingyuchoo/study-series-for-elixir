defmodule AgenticAiAgentWeb.MCPLive.Index do
  use AgenticAiAgentWeb, :live_view

  alias AgenticAiAgent.MCP
  alias AgenticAiAgent.MCP.{Server, Servers}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(2_000, self(), :refresh)

    {:ok, load(socket)}
  end

  @impl true
  def handle_info(:refresh, socket), do: {:noreply, load(socket)}

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    server = Servers.get!(id)
    {:ok, _} = Servers.delete(server)

    {:noreply,
     socket
     |> put_flash(:info, gettext("Deleted %{name}.", name: server.name))
     |> load()}
  end

  def handle_event("restart", %{"id" => id}, socket) do
    server = Servers.get!(id)
    :ok = case Servers.restart_one(server), do: (:ok -> :ok; _ -> :ok)

    {:noreply,
     socket
     |> put_flash(:info, gettext("Restarted %{name}.", name: server.name))
     |> load()}
  end

  def handle_event("toggle_enabled", %{"id" => id}, socket) do
    server = Servers.get!(id)

    case Servers.update(server, %{"enabled" => !server.enabled}) do
      {:ok, updated} ->
        flash = if updated.enabled, do: gettext("Enabled %{name}.", name: updated.name),
                                    else: gettext("Disabled %{name}.", name: updated.name)
        {:noreply, socket |> put_flash(:info, flash) |> load()}

      {:error, _cs} ->
        {:noreply, put_flash(socket, :error, gettext("Could not toggle %{name}.", name: server.name))}
    end
  end

  # ----- Data -----

  defp load(socket) do
    records = Servers.list_records()
    runtime_by_name = MCP.status() |> Map.new(fn s -> {s.name, s} end)

    rows =
      for %Server{} = r <- records do
        runtime = Map.get(runtime_by_name, r.name)
        %{
          record: r,
          status: (runtime && runtime.status) || (if r.enabled, do: :stopped, else: :disabled),
          tool_count: (runtime && runtime.tool_count) || 0,
          error: runtime && runtime.error
        }
      end

    socket
    |> assign(:rows, rows)
    |> assign(:configured, length(records))
  end

  # ----- Render -----

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path={@current_path} locale={@locale}>
      <div class="space-y-6">
        <header class="flex items-baseline justify-between gap-4">
          <div>
            <h1 class="text-2xl font-semibold">{gettext("MCP servers")}</h1>
            <p class="text-sm opacity-70">
              {gettext("MCP servers are persisted in the database and launched at boot. Add, edit, or remove them here — changes apply immediately.")}
            </p>
            <p class="text-xs opacity-60">
              {gettext("configured:")} {@configured} · {gettext("running:")} {Enum.count(@rows, &(&1.status == :ready))}
            </p>
          </div>
          <.link navigate={~p"/mcp/new"} class="rounded bg-black px-3 py-1.5 text-sm text-white">
            + {gettext("New server")}
          </.link>
        </header>

        <div :if={@rows == []} class="rounded border border-dashed p-6 text-center text-sm opacity-70">
          {gettext("No MCP servers configured yet. Click \"New server\" to add one.")}
        </div>

        <article :for={row <- @rows} class="space-y-3 rounded-lg border p-4">
          <header class="flex items-baseline justify-between gap-3">
            <div>
              <h2 class="text-lg font-semibold">{row.record.name}</h2>
              <p class="font-mono text-xs opacity-60">
                {row.record.command} {Enum.join(Server.args_list(row.record), " ")}
              </p>
              <p class="font-mono text-[10px] opacity-50">
                {gettext("risk:")} {row.record.risk_level}
                <span :if={!row.record.enabled}> · {gettext("disabled")}</span>
              </p>
            </div>
            <span class={["rounded px-2 py-0.5 text-[10px] font-mono uppercase", status_color(row.status)]}>
              {row.status}
            </span>
          </header>

          <p :if={row.error} class="rounded bg-red-50 dark:bg-red-950/40 p-2 text-xs text-red-700 dark:text-red-200">{row.error}</p>

          <details :if={row.tool_count > 0}>
            <summary class="cursor-pointer text-xs font-semibold uppercase tracking-wide opacity-70">
              {gettext("tools")} ({row.tool_count})
            </summary>
            <ul class="mt-2 space-y-1">
              <%= for t <- runtime_tools(row.record.name) do %>
                <li class="rounded border p-2 text-sm">
                  <code class="font-mono text-xs">mcp__{row.record.name}__{t["name"]}</code>
                  <p :if={t["description"]} class="mt-1 text-xs opacity-80">{t["description"]}</p>
                </li>
              <% end %>
            </ul>
          </details>

          <div class="flex flex-wrap items-center gap-2 pt-1">
            <.link navigate={~p"/mcp/#{row.record.id}/edit"} class="rounded border px-2 py-1 text-xs hover:bg-base-200">
              {gettext("Edit")}
            </.link>
            <button
              type="button"
              phx-click="toggle_enabled"
              phx-value-id={row.record.id}
              class="rounded border px-2 py-1 text-xs hover:bg-base-200"
            >
              <%= if row.record.enabled, do: gettext("Disable"), else: gettext("Enable") %>
            </button>
            <button
              type="button"
              phx-click="restart"
              phx-value-id={row.record.id}
              class="rounded border px-2 py-1 text-xs hover:bg-base-200"
              disabled={!row.record.enabled}
            >
              {gettext("Restart")}
            </button>
            <button
              type="button"
              phx-click="delete"
              phx-value-id={row.record.id}
              data-confirm={gettext("Delete %{name}?", name: row.record.name)}
              class="rounded border border-red-400 dark:border-red-600 px-2 py-1 text-xs text-red-700 dark:text-red-200 hover:bg-red-50 dark:hover:bg-red-950/40"
            >
              {gettext("Delete")}
            </button>
          </div>
        </article>
      </div>
    </Layouts.app>
    """
  end

  defp runtime_tools(name) do
    case MCP.info(name) do
      {:ok, info} -> info.tools
      _ -> []
    end
  end

  defp status_color(:ready), do: "bg-green-100 dark:bg-green-900/40 text-green-800 dark:text-green-200"
  defp status_color(:starting), do: "bg-yellow-100 dark:bg-yellow-900/40 text-yellow-800 dark:text-yellow-200"
  defp status_color(:initializing), do: "bg-yellow-100 dark:bg-yellow-900/40 text-yellow-800 dark:text-yellow-200"
  defp status_color(:requesting_tools), do: "bg-yellow-100 dark:bg-yellow-900/40 text-yellow-800 dark:text-yellow-200"
  defp status_color(:stopped), do: "bg-gray-200 dark:bg-gray-700 text-gray-700 dark:text-gray-200"
  defp status_color(:disabled), do: "bg-gray-100 dark:bg-gray-800 text-gray-500"
  defp status_color(:exited), do: "bg-red-100 dark:bg-red-900/40 text-red-800 dark:text-red-200"
  defp status_color(:failed), do: "bg-red-100 dark:bg-red-900/40 text-red-800 dark:text-red-200"
  defp status_color(_), do: "bg-gray-100 text-gray-800"
end
