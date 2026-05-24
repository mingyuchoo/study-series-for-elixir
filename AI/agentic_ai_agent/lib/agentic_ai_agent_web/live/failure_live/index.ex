defmodule AgenticAiAgentWeb.FailureLive.Index do
  use AgenticAiAgentWeb, :live_view

  alias AgenticAiAgent.Agent.Runtime
  alias AgenticAiAgent.Failures
  alias AgenticAiAgent.Failures.Clustering

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(AgenticAiAgent.PubSub, Runtime.runs_topic())
    end

    {:ok,
     socket
     |> assign(:cluster_state, :idle)
     |> assign(:clusters, [])
     |> assign(:cluster_singletons, 0)
     |> assign(:cluster_embedded, 0)
     |> assign(:cluster_error, nil)
     |> refresh()}
  end

  @impl true
  def handle_info({:runs, _, _}, socket), do: {:noreply, refresh(socket)}

  # Clustering is embedding-bound (one batch HTTP call); run it under
  # the Task supervisor so the LiveView keeps responding.
  def handle_info({:clusters_done, result}, socket) do
    {:noreply,
     socket
     |> assign(:cluster_state, result.status)
     |> assign(:clusters, result.clusters)
     |> assign(:cluster_singletons, result.singletons)
     |> assign(:cluster_embedded, result.embedded)
     |> assign(:cluster_error, result.reason)}
  end

  def handle_info(_other, socket), do: {:noreply, socket}

  @impl true
  def handle_event("reload_modes", _params, socket) do
    results = Failures.load_catalog_from_priv()

    {ok_results, err_results} =
      Enum.split_with(results, fn {_path, outcome} -> match?({:ok, _}, outcome) end)

    {kind, msg} =
      cond do
        results == [] ->
          {:error, gettext("No failure-mode YAML files found under priv/failures/.")}

        err_results == [] ->
          {:info,
           gettext("Reloaded %{n} failure mode(s) from priv/failures/.", n: length(ok_results))}

        true ->
          first_err = err_results |> List.first() |> elem(1) |> elem(1) |> inspect()

          {:error,
           gettext(
             "Reloaded %{ok}, %{fail} failed. First error: %{err}",
             ok: length(ok_results),
             fail: length(err_results),
             err: String.slice(first_err, 0, 160)
           )}
      end

    {:noreply, socket |> put_flash(kind, msg) |> refresh()}
  end

  def handle_event("cluster_failures", _params, socket) do
    parent = self()

    Task.Supervisor.start_child(AgenticAiAgent.Tools.TaskSupervisor, fn ->
      result = Clustering.cluster_recent()
      send(parent, {:clusters_done, result})
    end)

    {:noreply, assign(socket, :cluster_state, :running)}
  end

  defp refresh(socket) do
    modes = Failures.list_modes()
    counts = Failures.occurrence_counts()
    recent = Failures.list_recent_occurrences(25)

    socket
    |> assign(:modes, modes)
    |> assign(:counts, counts)
    |> assign(:recent, recent)
    |> assign(:total, Failures.total_count())
    |> assign(:unclassified, Failures.unclassified_count())
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path={@current_path} locale={@locale}>
      <div class="space-y-6">
        <header class="flex items-baseline justify-between gap-3">
          <div>
            <div class="eyebrow mb-2">{gettext("Failures")}</div>
            <h1 class="text-2xl font-semibold">{gettext("Failure modes")}</h1>
            <p class="text-sm opacity-70">
              {gettext(
                "Catalog of known failure shapes (authored as YAML under priv/failures/) and every occurrence the runtime has detected."
              )}
            </p>
            <p class="text-xs opacity-60">
              {length(@modes)} {gettext("modes in catalog")} ·
              <span class="font-mono">{@total}</span> {gettext("occurrences total")}
              <span :if={@unclassified > 0}>· {gettext("unclassified:")} <b>{@unclassified}</b></span>
            </p>
          </div>
          <button
            phx-click="reload_modes"
            type="button"
            class="rounded border px-3 py-1 text-xs hover:bg-base-200"
          >
            {gettext("Reload from files")}
          </button>
        </header>

        <section class="space-y-2">
          <div class="flex items-baseline justify-between gap-2">
            <h2 class="text-sm font-semibold uppercase tracking-wide opacity-70">
              {gettext("Semantic clusters")}
            </h2>
            <button
              phx-click="cluster_failures"
              type="button"
              disabled={@cluster_state == :running}
              class="rounded border px-3 py-1 text-xs hover:bg-base-200 disabled:opacity-50"
            >
              {if @cluster_state == :running,
                do: gettext("Clustering…"),
                else: gettext("Cluster recent failures")}
            </button>
          </div>

          <p :if={@cluster_state == :idle} class="text-xs opacity-70">
            {gettext(
              "Group recent reason strings by semantic similarity to surface hidden patterns the catalog can't see."
            )}
          </p>

          <p :if={@cluster_state == :no_failures} class="text-xs opacity-70">
            {gettext("No failures to cluster.")}
          </p>

          <p :if={@cluster_state == :embedding_failed} class="text-xs text-red-700 dark:text-red-300">
            {gettext("Clustering failed: %{r}", r: inspect(@cluster_error))}
          </p>

          <div :if={@cluster_state == :ok and @clusters == []} class="text-xs opacity-70">
            {gettext(
              "No recurring clusters (each failure was unique enough to land alone). %{n} singletons skipped.",
              n: @cluster_singletons
            )}
          </div>

          <ul :if={@cluster_state == :ok and @clusters != []} class="space-y-2">
            <li :for={c <- @clusters} class="rounded border border-base-300 p-3">
              <div class="flex items-baseline justify-between gap-2">
                <div class="flex items-baseline gap-2">
                  <span class="rounded bg-base-200 px-2 py-0.5 text-[10px] font-mono uppercase">
                    {gettext("cluster")} #{c.cluster_id}
                  </span>
                  <span class="rounded bg-emerald-100 dark:bg-emerald-900/40 text-emerald-800 dark:text-emerald-200 px-2 py-0.5 text-[10px] font-mono uppercase">
                    ×{c.size}
                  </span>
                  <span :if={c.mode_slug} class="font-mono text-xs opacity-70">
                    {c.mode_slug}
                  </span>
                  <span :if={is_nil(c.mode_slug)} class="font-mono text-xs opacity-60">
                    {gettext("(unclassified)")}
                  </span>
                </div>
                <span class="text-[11px] opacity-60">
                  {gettext("exemplar:")} {String.slice(c.exemplar_occurrence_id, 0, 8)}
                </span>
              </div>
              <p class="mt-1 font-mono text-[11px] opacity-80">{truncate(c.exemplar_reason, 240)}</p>
            </li>
          </ul>

          <p
            :if={@cluster_state == :ok and @cluster_singletons > 0}
            class="text-[11px] opacity-60"
          >
            {gettext("%{n} singleton failures (size 1) hidden.", n: @cluster_singletons)}
            {gettext("Embedded %{e} total.", e: @cluster_embedded)}
          </p>
        </section>

        <section class="space-y-2">
          <h2 class="text-sm font-semibold uppercase tracking-wide opacity-70">
            {gettext("Recent occurrences")}
          </h2>
          <div
            :if={@recent == []}
            class="rounded border border-dashed p-6 text-center text-sm opacity-70"
          >
            {gettext("No failures detected yet.")}
          </div>
          <ul :if={@recent != []} class="space-y-1">
            <li :for={o <- @recent} class="rounded border p-2 text-sm">
              <div class="flex items-baseline justify-between gap-2">
                <span class={[
                  "rounded px-2 py-0.5 text-[10px] font-mono uppercase",
                  severity_color(severity_of(o))
                ]}>
                  {severity_of(o)}
                </span>
                <span class="font-mono text-xs">
                  {(o.failure_mode && o.failure_mode.slug) || gettext("(unclassified)")}
                </span>
                <span class="ml-auto text-xs opacity-60">{format_time(o.inserted_at)}</span>
              </div>
              <p class="mt-1 font-mono text-[11px] opacity-80">{truncate(o.reason, 140)}</p>
              <p :if={o.run_id} class="mt-1 text-xs">
                <.link navigate={~p"/runs/#{o.run_id}"} class="font-mono opacity-70 hover:underline">
                  → {gettext("trace")} {String.slice(o.run_id, 0, 8)}
                </.link>
              </p>
            </li>
          </ul>
        </section>

        <section class="space-y-2">
          <h2 class="text-sm font-semibold uppercase tracking-wide opacity-70">
            {gettext("Catalog")}
          </h2>

          <div :for={{ftype, modes} <- group_by_type(@modes)} class="space-y-2">
            <h3 class="font-mono text-xs opacity-60">{ftype}</h3>
            <ul class="space-y-2">
              <li :for={m <- modes} class={["rounded border p-3", severity_border(m.severity)]}>
                <div class="flex items-baseline justify-between gap-2">
                  <div>
                    <span class="font-semibold">{m.name}</span>
                    <code class="ml-2 font-mono text-xs opacity-60">{m.slug}</code>
                  </div>
                  <div class="flex items-center gap-2">
                    <span class={[
                      "rounded px-2 py-0.5 text-[10px] font-mono uppercase",
                      severity_color(m.severity)
                    ]}>
                      {m.severity}
                    </span>
                    <span class="rounded bg-base-200 px-2 py-0.5 text-[10px] font-mono">
                      {Map.get(@counts, m.id, 0)}
                    </span>
                  </div>
                </div>

                <dl class="mt-2 space-y-1 text-xs">
                  <div :if={m.trigger_condition}>
                    <dt class="font-semibold opacity-60">{gettext("trigger:")}</dt>
                    <dd>{m.trigger_condition}</dd>
                  </div>
                  <div :if={m.example}>
                    <dt class="font-semibold opacity-60">{gettext("example:")}</dt>
                    <dd>{m.example}</dd>
                  </div>
                  <div :if={m.expected_recovery}>
                    <dt class="font-semibold opacity-60">{gettext("recovery:")}</dt>
                    <dd>{m.expected_recovery}</dd>
                  </div>
                  <div :if={m.detection_method}>
                    <dt class="font-semibold opacity-60">{gettext("detection:")}</dt>
                    <dd class="font-mono">{m.detection_method}</dd>
                  </div>
                </dl>
              </li>
            </ul>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end

  # ----- helpers -----

  defp group_by_type(modes) do
    modes
    |> Enum.group_by(& &1.failure_type)
    |> Enum.sort_by(fn {t, _} -> t end)
  end

  defp severity_of(%{failure_mode: %{severity: s}}) when is_binary(s), do: s
  defp severity_of(_), do: "unknown"

  defp severity_color("critical"),
    do: "bg-red-100 dark:bg-red-900/40 text-red-800 dark:text-red-200"

  defp severity_color("high"),
    do: "bg-orange-100 dark:bg-orange-900/40 text-orange-800 dark:text-orange-200"

  defp severity_color("medium"),
    do: "bg-yellow-100 dark:bg-yellow-900/40 text-yellow-800 dark:text-yellow-200"

  defp severity_color("low"),
    do: "bg-blue-100 dark:bg-blue-900/40 text-blue-800 dark:text-blue-200"

  defp severity_color(_), do: "bg-base-300"

  defp severity_border("critical"), do: "border-red-400 dark:border-red-600"
  defp severity_border("high"), do: "border-orange-300 dark:border-orange-700"
  defp severity_border("medium"), do: "border-yellow-300 dark:border-yellow-700"
  defp severity_border("low"), do: "border-blue-300 dark:border-blue-700"
  defp severity_border(_), do: ""

  defp truncate(nil, _), do: ""

  defp truncate(text, n) when is_binary(text) do
    if String.length(text) > n, do: String.slice(text, 0, n) <> "…", else: text
  end

  defp format_time(nil), do: "—"
  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
end
