defmodule AgenticAiAgentWeb.RunLive.Index do
  use AgenticAiAgentWeb, :live_view

  alias AgenticAiAgent.Traces
  alias AgenticAiAgent.Agent.Runtime

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(AgenticAiAgent.PubSub, Runtime.runs_topic())
    end

    {:ok, assign(socket, :runs, Traces.list_recent_runs(50))}
  end

  @impl true
  def handle_info({:runs, _action, _payload}, socket) do
    {:noreply, assign(socket, :runs, Traces.list_recent_runs(50))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path={@current_path} locale={@locale}>
      <div class="space-y-4">
        <header>
          <h1 class="text-2xl font-semibold">{gettext("Runs")}</h1>
          <p class="text-sm opacity-70">
            {gettext("Every chat turn opens a run. Steps and tool calls are persisted for replay and offline evaluation.")}
          </p>
        </header>

        <div :if={@runs == []} class="rounded border border-dashed p-6 text-center opacity-70">
          {gettext("No runs yet. Try chatting at")} <.link navigate={~p"/chat"} class="underline">/chat</.link>.
        </div>

        <ul :if={@runs != []} class="space-y-2">
          <li :for={run <- @runs} class="rounded border p-3">
            <div class="flex items-baseline justify-between gap-3">
              <.link navigate={~p"/runs/#{run.id}"} class="font-mono text-xs hover:underline">
                {String.slice(run.id, 0, 8)}
              </.link>
              <span class={[
                "rounded px-2 py-0.5 text-[10px] font-mono uppercase",
                status_color(run.status)
              ]}>
                {run.status}
              </span>
              <span class="ml-auto text-xs opacity-60">
                <span :if={run.cost_micro_usd && run.cost_micro_usd > 0} class="font-mono">
                  {AgenticAiAgent.LLM.Pricing.format(run.cost_micro_usd)} ·
                </span>
                {format_latency(run.latency_ms)} · {format_time(run.inserted_at)}
              </span>
            </div>
            <p class="mt-2 truncate text-sm">{truncate(run.user_input, 200)}</p>
            <p :if={run.final_answer} class="mt-1 truncate text-xs opacity-70">
              → {truncate(run.final_answer, 200)}
            </p>
          </li>
        </ul>
      </div>
    </Layouts.app>
    """
  end

  defp status_color("done"), do: "bg-green-100 dark:bg-green-900/40 text-green-800 dark:text-green-200"
  defp status_color("failed"), do: "bg-red-100 dark:bg-red-900/40 text-red-800 dark:text-red-200"
  defp status_color("running"), do: "bg-yellow-100 dark:bg-yellow-900/40 text-yellow-800 dark:text-yellow-200"
  defp status_color("awaiting_approval"), do: "bg-orange-100 dark:bg-orange-900/40 text-orange-800 dark:text-orange-200"
  defp status_color("cancelled"), do: "bg-base-300 text-base-content"
  defp status_color(_), do: "bg-gray-100 text-gray-800"

  defp format_latency(nil), do: "—"
  defp format_latency(ms) when ms < 1000, do: "#{ms} ms"
  defp format_latency(ms), do: "#{Float.round(ms / 1000, 2)} s"

  defp format_time(nil), do: "—"

  defp format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  end

  defp truncate(nil, _n), do: ""

  defp truncate(text, n) when is_binary(text) do
    if String.length(text) > n, do: String.slice(text, 0, n) <> "…", else: text
  end
end
