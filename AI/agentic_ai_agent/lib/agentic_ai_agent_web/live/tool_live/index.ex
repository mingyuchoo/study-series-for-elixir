defmodule AgenticAiAgentWeb.ToolLive.Index do
  use AgenticAiAgentWeb, :live_view

  alias AgenticAiAgent.Tools.Registry, as: ToolRegistry

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :tools, load_tools())}
  end

  defp load_tools do
    for {name, _entry} <- ToolRegistry.list() do
      ToolRegistry.metadata(name)
    end
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.name)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path={@current_path} locale={@locale}>
      <div class="space-y-6">
        <header>
          <h1 class="text-2xl font-semibold">{gettext("Tools")}</h1>
          <p class="text-sm opacity-70">
            {gettext("Tool Contract catalog. Each entry shows what the LLM sees plus the runtime-only fields — preconditions, side effects, known failure modes, and retry policy.")}
          </p>
          <p class="text-xs opacity-60">{length(@tools)} {gettext("tools registered")}</p>
        </header>

        <article :for={t <- @tools} class="space-y-3 rounded-lg border p-4">
          <header class="flex items-baseline justify-between gap-3">
            <div>
              <code class="font-mono text-lg font-semibold">{t.name}</code>
              <p :if={t.source} class="font-mono text-[10px] opacity-60">
                {gettext("from MCP:")} {inspect(t.source)}
              </p>
            </div>
            <span class={["rounded px-2 py-0.5 text-[10px] font-mono uppercase", risk_color(t.risk_level)]}>
              {t.risk_level}
            </span>
          </header>

          <p class="text-sm opacity-80">{t.description}</p>

          <div :if={t.side_effects != []} class="space-y-1">
            <div class="font-mono text-xs opacity-60">{gettext("Side effects")}</div>
            <ul class="ml-4 list-disc space-y-0.5 text-sm">
              <li :for={se <- t.side_effects}>{se}</li>
            </ul>
          </div>

          <div :if={t.failure_modes != []} class="space-y-1">
            <div class="font-mono text-xs opacity-60">{gettext("Known failure modes")}</div>
            <ul class="flex flex-wrap gap-1">
              <li :for={slug <- t.failure_modes}>
                <.link navigate={~p"/failures"} class="rounded bg-base-200 px-2 py-0.5 font-mono text-[10px] hover:underline">
                  {slug}
                </.link>
              </li>
            </ul>
          </div>

          <div :if={retry_policy_present?(t.retry_policy)} class="space-y-1">
            <div class="font-mono text-xs opacity-60">{gettext("Retry policy")}</div>
            <pre class="overflow-x-auto rounded bg-base-200 p-2 text-xs">{Jason.encode!(t.retry_policy, pretty: true)}</pre>
          </div>

          <details>
            <summary class="cursor-pointer text-xs font-semibold uppercase tracking-wide opacity-70">
              {gettext("input schema")}
            </summary>
            <pre class="mt-2 overflow-x-auto rounded bg-base-200 p-3 text-xs">{Jason.encode!(t.input_schema, pretty: true)}</pre>
          </details>

          <details>
            <summary class="cursor-pointer text-xs font-semibold uppercase tracking-wide opacity-70">
              {gettext("output schema")}
            </summary>
            <pre class="mt-2 overflow-x-auto rounded bg-base-200 p-3 text-xs">{Jason.encode!(t.output_schema, pretty: true)}</pre>
          </details>
        </article>
      </div>
    </Layouts.app>
    """
  end

  defp risk_color(:low), do: "bg-blue-100 dark:bg-blue-900/40 text-blue-800 dark:text-blue-200"
  defp risk_color(:medium), do: "bg-yellow-100 dark:bg-yellow-900/40 text-yellow-800 dark:text-yellow-200"
  defp risk_color(:high), do: "bg-orange-100 dark:bg-orange-900/40 text-orange-800 dark:text-orange-200"
  defp risk_color(:critical), do: "bg-red-100 dark:bg-red-900/40 text-red-800 dark:text-red-200"
  defp risk_color(_), do: "bg-base-200"

  defp retry_policy_present?(map) when is_map(map) and map_size(map) > 0 do
    Map.get(map, :max_retries, Map.get(map, "max_retries", 0)) > 0
  end

  defp retry_policy_present?(_), do: false
end
