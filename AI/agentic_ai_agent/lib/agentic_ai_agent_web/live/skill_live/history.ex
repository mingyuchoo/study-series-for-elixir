defmodule AgenticAiAgentWeb.SkillLive.History do
  use AgenticAiAgentWeb, :live_view

  alias AgenticAiAgent.Skills
  alias AgenticAiAgentWeb.Diff

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    versions = Skills.list_versions(slug)
    current_body = read_current(slug)

    {:ok,
     socket
     |> assign(:slug, slug)
     |> assign(:versions, versions)
     |> assign(:current_body, current_body)
     |> assign(:selected_id, nil)
     |> assign(:error, nil)}
  end

  @impl true
  def handle_event("select", %{"id" => id}, socket) do
    {:noreply, assign(socket, :selected_id, id)}
  end

  def handle_event("restore", %{"id" => id}, socket) do
    version = Skills.get_version!(id)

    case Skills.restore_version(version) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info,
           gettext("Restored skill from version %{sha}.", sha: Skills.short_sha(version.sha))
         )
         |> push_navigate(to: ~p"/skills")}

      {:error, reason} ->
        {:noreply, assign(socket, :error, gettext("Restore failed: %{r}", r: inspect(reason)))}
    end
  end

  defp read_current(slug) do
    path = Skills.source_path(slug)
    if File.exists?(path), do: File.read!(path), else: ""
  rescue
    _ -> ""
  end

  defp selected_version(versions, id), do: Enum.find(versions, &(&1.id == id))

  # ----- Render -----

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns, :selected, selected_version(assigns.versions, assigns.selected_id))

    ~H"""
    <Layouts.app flash={@flash} current_path={@current_path} locale={@locale}>
      <div class="space-y-6">
        <header class="flex items-baseline justify-between">
          <div>
            <div class="eyebrow mb-2">{gettext("Skills")} / {gettext("History")}</div>
            <h1 class="text-2xl font-semibold">{@slug}</h1>
          </div>
          <.link navigate={~p"/skills"} class="text-xs opacity-70 hover:underline">
            ← {gettext("Back to skills")}
          </.link>
        </header>

        <div :if={@error} class="rounded border border-red-400 dark:border-red-600 bg-red-50 dark:bg-red-950/40 p-2 text-xs text-red-700 dark:text-red-200">
          {@error}
        </div>

        <div :if={@versions == []} class="rounded border border-dashed p-6 text-center text-sm opacity-70">
          {gettext("No versions yet. Edits made through the editor will be recorded here.")}
        </div>

        <div :if={@versions != []} class="grid grid-cols-1 gap-4 lg:grid-cols-3">
          <section class="rounded-lg border border-base-300 bg-base-200 p-3 lg:col-span-1">
            <div class="mb-2 eyebrow">{gettext("Versions")} ({length(@versions)})</div>
            <ul class="space-y-1">
              <li :for={v <- @versions}>
                <button
                  type="button"
                  phx-click="select"
                  phx-value-id={v.id}
                  class={[
                    "block w-full rounded p-2 text-left text-xs hover:bg-base-300/40",
                    @selected_id == v.id && "bg-base-300/60"
                  ]}
                >
                  <div class="flex items-baseline justify-between">
                    <code class="font-mono text-[11px]">{Skills.short_sha(v.sha)}</code>
                    <span class="text-[10px] opacity-60">{format_time(v.inserted_at)}</span>
                  </div>
                  <p :if={v.reason} class="mt-0.5 truncate text-[11px] opacity-80">{v.reason}</p>
                </button>
              </li>
            </ul>
          </section>

          <section class="rounded-lg border border-base-300 bg-base-200 p-3 lg:col-span-2">
            <div :if={!@selected} class="text-sm opacity-60">
              {gettext("Pick a version on the left to compare with the current file.")}
            </div>

            <div :if={@selected}>
              <div class="mb-3 flex flex-wrap items-baseline justify-between gap-2">
                <div>
                  <div class="eyebrow mb-1">{gettext("Diff: selected → current")}</div>
                  <p class="font-mono text-[11px] opacity-70">
                    {Skills.short_sha(@selected.sha)} · {format_time(@selected.inserted_at)}
                    <span :if={@selected.reason}> · {@selected.reason}</span>
                  </p>
                </div>
                <button
                  type="button"
                  phx-click="restore"
                  phx-value-id={@selected.id}
                  data-confirm={gettext("Restore skill to this version? A new snapshot of the current state will be created first.")}
                  class="rounded-full border border-base-300 px-4 py-1 text-xs font-medium hover:bg-base-300/40"
                >
                  {gettext("Restore this version")}
                </button>
              </div>

              <.diff_view from={@selected.body} to={@current_body} />
            </div>
          </section>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :from, :string, required: true
  attr :to, :string, required: true

  defp diff_view(assigns) do
    rows =
      for {op, lines} <- Diff.lines(assigns.from, assigns.to),
          line <- lines,
          do: {op, line}

    assigns = assign(assigns, :rows, rows)

    ~H"""
    <div class="overflow-x-auto rounded bg-base-100 p-3 font-mono text-xs leading-snug whitespace-pre">
      <div :for={{op, line} <- @rows} class={diff_line_class(op)}>{diff_marker(op)}{line}</div>
    </div>
    """
  end

  defp diff_marker(:eq), do: "  "
  defp diff_marker(:del), do: "- "
  defp diff_marker(:ins), do: "+ "

  defp diff_line_class(:eq), do: "opacity-60"
  defp diff_line_class(:del), do: "bg-red-100 dark:bg-red-900/30 text-red-800 dark:text-red-200"
  defp diff_line_class(:ins), do: "bg-emerald-100 dark:bg-emerald-900/30 text-emerald-800 dark:text-emerald-200"

  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  defp format_time(_), do: "—"
end
