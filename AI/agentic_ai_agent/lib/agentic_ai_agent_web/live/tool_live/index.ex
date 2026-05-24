defmodule AgenticAiAgentWeb.ToolLive.Index do
  use AgenticAiAgentWeb, :live_view

  alias AgenticAiAgent.Tools.Registry, as: ToolRegistry
  alias AgenticAiAgent.Tools.Specs

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(AgenticAiAgent.PubSub, ToolRegistry.pubsub_topic())
    end

    {:ok, assign(socket, :tools, load_tools())}
  end

  defp load_tools do
    for {name, _entry} <- ToolRegistry.list() do
      meta = ToolRegistry.metadata(name)
      spec = Specs.get_spec_by_name(name)

      meta && Map.put(meta, :spec_id, spec && spec.id)
    end
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.name)
  end

  @impl true
  def handle_event("toggle_enabled", %{"name" => name}, socket) do
    current = ToolRegistry.enabled?(name)

    case ToolRegistry.update_spec(name, %{"enabled" => !current}) do
      {:ok, _spec} ->
        flash =
          if current,
            do: gettext("Disabled %{name}.", name: name),
            else: gettext("Enabled %{name}.", name: name)

        {:noreply, socket |> put_flash(:info, flash) |> assign(:tools, load_tools())}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, gettext("Could not update %{name}: %{r}.", name: name, r: inspect(reason)))}
    end
  end

  @impl true
  def handle_info({:tool, :updated, _name}, socket) do
    {:noreply, assign(socket, :tools, load_tools())}
  end

  def handle_info(_other, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path={@current_path} locale={@locale}>
      <div class="space-y-6">
        <header>
          <div class="eyebrow mb-2">{gettext("Tools")}</div>
          <h1 class="text-2xl font-semibold">{gettext("Tools")}</h1>
          <p class="text-sm opacity-70">
            {gettext("Tool Contract catalog. risk_level and enabled can be edited from here — changes apply to the runtime immediately. Code-defined fields (purpose, schemas, failure_modes) remain read-only.")}
          </p>
          <p class="text-xs opacity-60">{length(@tools)} {gettext("tools registered")}</p>
        </header>

        <article :for={t <- @tools} class={["space-y-3 rounded-lg border p-4", if(t.enabled, do: "", else: "opacity-60")]}>
          <header class="flex items-baseline justify-between gap-3">
            <div>
              <code class="font-mono text-lg font-semibold">{t.name}</code>
              <p :if={t.source} class="font-mono text-[10px] opacity-60">
                {gettext("from MCP:")} {inspect(t.source)}
              </p>
            </div>
            <div class="flex items-center gap-2">
              <span :if={!t.enabled} class="rounded bg-base-300 px-2 py-0.5 text-[10px] font-mono uppercase">
                {gettext("disabled")}
              </span>
              <span class={["rounded px-2 py-0.5 text-[10px] font-mono uppercase", risk_color(t.risk_level)]}>
                {t.risk_level}
              </span>
            </div>
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

          <div :if={t.spec_id} class="flex flex-wrap items-center gap-2 pt-1">
            <button
              type="button"
              phx-click="toggle_enabled"
              phx-value-name={t.name}
              class="rounded border px-2 py-1 text-xs hover:bg-base-200"
            >
              <%= if t.enabled, do: gettext("Disable"), else: gettext("Enable") %>
            </button>
            <.link
              navigate={~p"/tools/#{t.spec_id}/edit"}
              class="rounded border px-2 py-1 text-xs hover:bg-base-200"
            >
              {gettext("Edit")}
            </.link>
          </div>
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
