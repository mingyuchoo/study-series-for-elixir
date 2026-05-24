defmodule AgenticAiAgentWeb.NotificationLive.Index do
  use AgenticAiAgentWeb, :live_view

  alias AgenticAiAgent.Notifications

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(AgenticAiAgent.PubSub, Notifications.pubsub_topic())
    end

    {:ok,
     socket
     |> assign(:filter, "all")
     |> load()}
  end

  @impl true
  def handle_event("filter", %{"f" => f}, socket),
    do: {:noreply, socket |> assign(:filter, f) |> load()}

  def handle_event("mark_read", %{"id" => id}, socket) do
    _ = Notifications.mark_read!(Notifications.get!(id))
    {:noreply, load(socket)}
  end

  def handle_event("mark_all_read", _params, socket) do
    n = Notifications.mark_all_read!()

    {:noreply,
     socket
     |> put_flash(:info, gettext("Marked %{n} notifications as read.", n: n))
     |> load()}
  end

  @impl true
  def handle_info({:notification, :new, _n}, socket), do: {:noreply, load(socket)}
  def handle_info(_other, socket), do: {:noreply, socket}

  defp load(socket) do
    socket
    |> assign(:notifications, Notifications.list(unread_only: socket.assigns.filter == "unread"))
    |> assign(:unread_count, Notifications.unread_count())
  end

  # ----- Render -----

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path={@current_path} locale={@locale}>
      <div class="space-y-6">
        <header class="flex items-baseline justify-between gap-3">
          <div>
            <div class="eyebrow mb-2">{gettext("Notifications")}</div>
            <h1 class="text-2xl font-semibold">
              {gettext("Notifications")}
              <span :if={@unread_count > 0} class="ml-2 rounded-full bg-amber-100 dark:bg-amber-900/40 text-amber-800 dark:text-amber-200 px-2 py-0.5 text-xs">
                {@unread_count} {gettext("unread")}
              </span>
            </h1>
            <p class="text-sm opacity-70">
              {gettext("Autonomous actions taken by the system. Auto-promotes, auto-rollbacks, safety blocks, and dry-run previews land here.")}
            </p>
          </div>
          <button
            :if={@unread_count > 0}
            type="button"
            phx-click="mark_all_read"
            class="rounded-full border border-base-300 px-4 py-1 text-xs hover:bg-base-300/40"
          >
            {gettext("Mark all as read")}
          </button>
        </header>

        <form phx-change="filter" class="flex items-center gap-2 text-xs">
          <span class="eyebrow">{gettext("Filter")}</span>
          <select name="f" class="rounded-full border border-base-300 bg-base-100 px-3 py-1">
            <option :for={f <- ~w(all unread)} value={f} selected={f == @filter}>{f}</option>
          </select>
        </form>

        <div :if={@notifications == []} class="rounded border border-dashed p-6 text-center text-sm opacity-70">
          {gettext("No notifications.")}
        </div>

        <ul :if={@notifications != []} class="space-y-2">
          <li
            :for={n <- @notifications}
            class={[
              "rounded-lg border p-3",
              if(n.read_at, do: "border-base-300 bg-base-200 opacity-70", else: "border-amber-300 dark:border-amber-700 bg-amber-50 dark:bg-amber-950/40")
            ]}
          >
            <div class="flex items-baseline justify-between gap-2">
              <div class="flex items-baseline gap-2">
                <span class={["rounded px-2 py-0.5 text-[10px] font-mono uppercase", kind_color(n.kind)]}>
                  {n.kind}
                </span>
                <span class="text-sm font-medium">{n.subject}</span>
              </div>
              <span class="text-xs opacity-60">{format_time(n.inserted_at)}</span>
            </div>

            <p :if={n.body} class="mt-1 whitespace-pre-wrap text-xs opacity-80">{n.body}</p>

            <div class="mt-2 flex flex-wrap items-center gap-2 text-[11px]">
              <.link :if={n.card_slug} navigate={~p"/improvements"} class="font-mono opacity-70 hover:underline">
                /improvements
              </.link>
              <code :if={n.proposal_id} class="font-mono opacity-60">
                proposal {String.slice(n.proposal_id, 0, 8)}
              </code>
              <button
                :if={!n.read_at}
                type="button"
                phx-click="mark_read"
                phx-value-id={n.id}
                class="ml-auto rounded-full border border-base-300 px-3 py-0.5 hover:bg-base-300/40"
              >
                {gettext("Mark read")}
              </button>
            </div>
          </li>
        </ul>
      </div>
    </Layouts.app>
    """
  end

  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  defp format_time(_), do: "—"

  defp kind_color("auto_promote"),
    do: "bg-green-100 dark:bg-green-900/40 text-green-800 dark:text-green-200"

  defp kind_color("auto_rollback"),
    do: "bg-red-100 dark:bg-red-900/40 text-red-800 dark:text-red-200"

  defp kind_color("safety_blocked"),
    do: "bg-orange-100 dark:bg-orange-900/40 text-orange-800 dark:text-orange-200"

  defp kind_color("dry_run"),
    do: "bg-purple-100 dark:bg-purple-900/40 text-purple-800 dark:text-purple-200"

  defp kind_color(_), do: "bg-base-300"
end
