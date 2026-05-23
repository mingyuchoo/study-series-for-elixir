defmodule AgenticAiAgentWeb.MCPLive.Index do
  use AgenticAiAgentWeb, :live_view

  alias AgenticAiAgent.MCP

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(2_000, self(), :refresh)

    {:ok,
     socket
     |> assign(:servers, load_servers())
     |> assign(:configured, configured_count())}
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, assign(socket, :servers, load_servers())}
  end

  defp load_servers do
    for name <- MCP.list_servers() do
      case MCP.info(name) do
        {:ok, info} -> info
        _ -> %{name: name, status: :unknown, error: nil, tools: [], risk_level: :unknown}
      end
    end
  end

  defp configured_count,
    do: Application.get_env(:agentic_ai_agent, :mcp_servers, []) |> length()

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path={@current_path} locale={@locale}>
      <div class="space-y-6">
        <header>
          <h1 class="text-2xl font-semibold">{gettext("MCP servers")}</h1>
          <p class="text-sm opacity-70">
            {gettext("Servers configured via :mcp_servers in config/runtime.exs are launched at boot, the handshake is run, and discovered tools are registered under the name mcp__<server>__<tool>.")}
          </p>
          <p class="text-xs opacity-60">{gettext("configured:")} {@configured} · {gettext("active:")} {length(@servers)}</p>
        </header>

        <div :if={@servers == []} class="rounded border border-dashed p-6 text-center text-sm opacity-70">
          {gettext("No MCP servers connected. Add entries under :mcp_servers in config/runtime.exs and restart.")}
        </div>

        <article :for={s <- @servers} class="space-y-3 rounded-lg border p-4">
          <header class="flex items-baseline justify-between">
            <div>
              <h2 class="text-lg font-semibold">{s.name}</h2>
              <p class="font-mono text-xs opacity-60">{gettext("risk:")} {s.risk_level}</p>
            </div>
            <span class={["rounded px-2 py-0.5 text-[10px] font-mono uppercase", status_color(s.status)]}>
              {s.status}
            </span>
          </header>

          <p :if={s.error} class="rounded bg-red-50 dark:bg-red-950/40 p-2 text-xs text-red-700 dark:text-red-200">{s.error}</p>

          <details>
            <summary class="cursor-pointer text-xs font-semibold uppercase tracking-wide opacity-70">
              {gettext("tools")} ({length(s.tools)})
            </summary>
            <ul class="mt-2 space-y-1">
              <li :for={t <- s.tools} class="rounded border p-2 text-sm">
                <div class="flex items-baseline justify-between">
                  <code class="font-mono text-xs">mcp__{s.name}__{t["name"]}</code>
                </div>
                <p :if={t["description"]} class="mt-1 text-xs opacity-80">{t["description"]}</p>
              </li>
            </ul>
          </details>
        </article>
      </div>
    </Layouts.app>
    """
  end

  defp status_color(:ready), do: "bg-green-100 dark:bg-green-900/40 text-green-800 dark:text-green-200"
  defp status_color(:starting), do: "bg-yellow-100 dark:bg-yellow-900/40 text-yellow-800 dark:text-yellow-200"
  defp status_color(:initializing), do: "bg-yellow-100 dark:bg-yellow-900/40 text-yellow-800 dark:text-yellow-200"
  defp status_color(:requesting_tools), do: "bg-yellow-100 dark:bg-yellow-900/40 text-yellow-800 dark:text-yellow-200"
  defp status_color(:exited), do: "bg-red-100 dark:bg-red-900/40 text-red-800 dark:text-red-200"
  defp status_color(:failed), do: "bg-red-100 dark:bg-red-900/40 text-red-800 dark:text-red-200"
  defp status_color(_), do: "bg-gray-100 text-gray-800"
end
