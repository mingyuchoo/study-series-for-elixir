defmodule AgenticAiAgentWeb.EvalLive.Index do
  use AgenticAiAgentWeb, :live_view

  alias AgenticAiAgent.{Design, Eval}

  @refresh_ms 3_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(AgenticAiAgent.PubSub, Eval.pubsub_topic())
      :timer.send_interval(@refresh_ms, self(), :tick)
    end

    cards = Design.list_cards()
    default_slug = (List.first(cards) || %{}) |> Map.get(:slug)

    {:ok,
     socket
     |> assign(:runs, Eval.list_eval_runs(50))
     |> assign(:cards, cards)
     |> assign(:selected_slug, default_slug)
     |> assign(:starting?, false)}
  end

  # ----- Events -----

  @impl true
  def handle_event("select_card", %{"slug" => slug}, socket),
    do: {:noreply, assign(socket, :selected_slug, slug)}

  def handle_event("run", _params, %{assigns: %{selected_slug: nil}} = socket) do
    {:noreply, put_flash(socket, :error, gettext("Pick a card first."))}
  end

  def handle_event("run", _params, socket) do
    slug = socket.assigns.selected_slug

    case Eval.run_card_async(slug) do
      :ok ->
        {:noreply,
         socket
         |> assign(:starting?, true)
         |> put_flash(:info, gettext("Started eval for card %{slug}.", slug: slug))}

      {:error, :card_not_found} ->
        {:noreply, put_flash(socket, :error, gettext("Card not found: %{slug}.", slug: slug))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to start eval: %{r}.", r: inspect(reason)))}
    end
  end

  # ----- PubSub + ticks -----

  @impl true
  def handle_info({:eval, :started, _info}, socket) do
    {:noreply, socket |> assign(:starting?, false) |> refresh()}
  end

  def handle_info({:eval, :finished, {:ok, eval_run}}, socket) do
    {:noreply,
     socket
     |> put_flash(:info,
       gettext("Eval %{id} done: %{p}/%{t} passed (avg %{a}).",
         id: String.slice(eval_run.id, 0, 8),
         p: eval_run.passed_cases,
         t: eval_run.total_cases,
         a: format(eval_run.average_score)
       )
     )
     |> refresh()}
  end

  def handle_info({:eval, :finished, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:starting?, false)
     |> put_flash(:error, gettext("Eval failed: %{r}.", r: inspect(reason)))
     |> refresh()}
  end

  def handle_info(:tick, socket) do
    # Only refresh while at least one run is mid-flight; otherwise spare the DB.
    if Enum.any?(socket.assigns.runs, &(&1.status == "running")) or socket.assigns.starting? do
      {:noreply, refresh(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_other, socket), do: {:noreply, socket}

  defp refresh(socket), do: assign(socket, :runs, Eval.list_eval_runs(50))

  # ----- Render -----

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path={@current_path} locale={@locale}>
      <div class="space-y-6">
        <header class="flex items-baseline justify-between gap-3">
          <div>
            <h1 class="text-2xl font-semibold">{gettext("Eval runs")}</h1>
            <p class="text-sm opacity-70">
              {gettext("Each run executes a golden dataset against an agentic card and scores every case with the heuristic rubric.")}
            </p>
          </div>
        </header>

        <section class="rounded-lg border bg-base-100 p-4">
          <div class="mb-2 text-xs font-semibold uppercase tracking-wide opacity-70">
            {gettext("Run a new eval")}
          </div>

          <div :if={@cards == []} class="text-sm opacity-70">
            {gettext("No cards available. Add one under priv/cards/ and reload.")}
          </div>

          <div :if={@cards != []} class="flex flex-wrap items-center gap-3">
            <label class="text-xs opacity-70" for="card_slug">{gettext("Card")}</label>
            <select
              id="card_slug"
              phx-change="select_card"
              name="slug"
              class="rounded border px-2 py-1 text-sm"
              disabled={@starting?}
            >
              <option :for={c <- @cards} value={c.slug} selected={c.slug == @selected_slug}>
                {c.name} ({c.slug})
              </option>
            </select>

            <button
              type="button"
              phx-click="run"
              disabled={@starting? or @selected_slug == nil}
              class="rounded bg-black px-3 py-1.5 text-sm text-white disabled:opacity-50"
            >
              {if @starting?, do: gettext("Starting…"), else: gettext("Run eval")}
            </button>

            <span :if={Enum.any?(@runs, &(&1.status == "running"))} class="text-xs text-amber-700 dark:text-amber-300">
              ⟳ {gettext("A run is in progress — list refreshes automatically.")}
            </span>
          </div>
        </section>

        <div :if={@runs == []} class="rounded border border-dashed p-6 text-center text-sm opacity-70">
          {gettext("No eval runs yet. Run one above or use mix agent.eval.")}
        </div>

        <ul :if={@runs != []} class="space-y-2">
          <li :for={r <- @runs} class="rounded border p-3">
            <div class="flex items-baseline justify-between">
              <.link navigate={~p"/evals/#{r.id}"} class="font-mono text-xs hover:underline">
                {String.slice(r.id, 0, 8)}
              </.link>
              <span class={["rounded px-2 py-0.5 text-[10px] font-mono uppercase", status_color(r.status)]}>
                {r.status}
              </span>
              <span class="ml-auto text-xs opacity-60">{format_time(r.inserted_at)}</span>
            </div>
            <div class="mt-1 text-sm">
              <span class="font-semibold">{r.passed_cases}/{r.total_cases}</span>
              {gettext("passed · avg score")}
              <span class={[score_color(r.average_score, r.pass_threshold), "font-mono"]}>
                {format(r.average_score)}
              </span>
              · {gettext("threshold")} {format(r.pass_threshold)}
            </div>
            <p class="font-mono text-[10px] opacity-50">{r.golden_path}</p>
          </li>
        </ul>
      </div>
    </Layouts.app>
    """
  end

  defp status_color("done"), do: "bg-green-100 dark:bg-green-900/40 text-green-800 dark:text-green-200"
  defp status_color("failed"), do: "bg-red-100 dark:bg-red-900/40 text-red-800 dark:text-red-200"
  defp status_color("running"), do: "bg-yellow-100 dark:bg-yellow-900/40 text-yellow-800 dark:text-yellow-200"
  defp status_color(_), do: "bg-gray-100 text-gray-800"

  defp score_color(nil, _), do: "opacity-60"
  defp score_color(_, nil), do: "opacity-60"
  defp score_color(s, t) when s >= t, do: "text-green-700"
  defp score_color(_, _), do: "text-red-700 dark:text-red-200"

  defp format(nil), do: "—"
  defp format(n) when is_number(n), do: :io_lib.format("~5.3f", [n]) |> List.to_string()

  defp format_time(nil), do: "—"
  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
end
