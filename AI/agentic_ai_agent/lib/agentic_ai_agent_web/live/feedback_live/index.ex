defmodule AgenticAiAgentWeb.FeedbackLive.Index do
  use AgenticAiAgentWeb, :live_view

  alias AgenticAiAgent.Feedback

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:status_filter, "pending")
     |> load()}
  end

  # ----- Events -----

  @impl true
  def handle_event("filter", %{"status" => status}, socket) do
    {:noreply, socket |> assign(:status_filter, status) |> load()}
  end

  def handle_event("promote", %{"candidate_id" => id, "corrected" => corrected}, socket) do
    candidate = Feedback.get!(id)
    corrected = String.trim(corrected || "")

    case Feedback.promote!(candidate, corrected_answer: corrected, by: "hitl-user") do
      {:ok, _updated} ->
        {:noreply,
         socket
         |> put_flash(:info,
           gettext("Promoted to %{path}. The next eval cycle will include it.",
             path: relative(Feedback.regressions_path())
           )
         )
         |> load()}

      {:error, :corrected_answer_required} ->
        {:noreply,
         put_flash(socket, :error, gettext("Type the corrected answer first."))}

      {:error, :already_promoted} ->
        {:noreply, put_flash(socket, :error, gettext("Already promoted."))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, gettext("Promote failed: %{r}", r: inspect(reason)))}
    end
  end

  def handle_event("dismiss", %{"candidate_id" => id, "reason" => reason}, socket) do
    candidate = Feedback.get!(id)
    _ = Feedback.dismiss!(candidate, reason: reason || "", by: "hitl-user")
    {:noreply, socket |> put_flash(:info, gettext("Candidate dismissed.")) |> load()}
  end

  # ----- Data -----

  defp load(socket) do
    status =
      case socket.assigns.status_filter do
        "all" -> nil
        s -> s
      end

    assign(socket, :candidates, Feedback.list(status: status))
  end

  defp relative(absolute) when is_binary(absolute) do
    case String.split(absolute, "/priv/", parts: 2) do
      [_, rest] -> "priv/" <> rest
      _ -> absolute
    end
  end

  # ----- Render -----

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path={@current_path} locale={@locale}>
      <div class="space-y-6">
        <header>
          <div class="eyebrow mb-2">{gettext("Feedback")}</div>
          <h1 class="text-2xl font-semibold">{gettext("Golden candidates")}</h1>
          <p class="text-sm opacity-70">
            {gettext("User-flagged chat answers awaiting curation. Type the corrected answer and promote to grow the regression set at priv/eval/golden/regressions.jsonl.")}
          </p>
        </header>

        <!-- Filter -->
        <form phx-change="filter" class="flex flex-wrap items-center gap-2 text-xs">
          <span class="eyebrow">{gettext("Filter")}</span>
          <select name="status" class="rounded-full border border-base-300 bg-base-100 px-3 py-1">
            <option :for={s <- ~w(all pending promoted dismissed)} value={s} selected={s == @status_filter}>
              {s}
            </option>
          </select>
          <span class="opacity-60">{length(@candidates)} {gettext("shown")}</span>
        </form>

        <div :if={@candidates == []} class="rounded border border-dashed p-6 text-center text-sm opacity-70">
          {gettext("No candidates match this filter. Click 👎 on a chat answer to add one.")}
        </div>

        <ul :if={@candidates != []} class="space-y-3">
          <li :for={c <- @candidates} class="rounded-lg border border-base-300 bg-base-200 p-3">
            <div class="flex flex-wrap items-baseline justify-between gap-2">
              <div class="flex items-baseline gap-2">
                <span class={["rounded px-2 py-0.5 text-[10px] font-mono uppercase", status_color(c.status)]}>
                  {c.status}
                </span>
                <code :if={c.target_card_slug} class="font-mono text-xs opacity-70">→ {c.target_card_slug}</code>
                <.link
                  :if={c.run_id}
                  navigate={~p"/runs/#{c.run_id}"}
                  class="font-mono text-xs opacity-70 hover:underline"
                >
                  run {String.slice(c.run_id, 0, 8)}
                </.link>
              </div>
              <span class="text-xs opacity-60">{format_time(c.inserted_at)}</span>
            </div>

            <!-- User input -->
            <div class="mt-2">
              <div class="eyebrow mb-1">{gettext("User asked")}</div>
              <p class="whitespace-pre-wrap text-sm">{c.user_input}</p>
            </div>

            <!-- Agent answer -->
            <div :if={c.assistant_answer} class="mt-2">
              <div class="eyebrow mb-1">{gettext("Agent answered")}</div>
              <p class="whitespace-pre-wrap text-sm opacity-80">{c.assistant_answer}</p>
            </div>

            <!-- User note -->
            <p :if={c.user_note} class="mt-1 text-xs italic opacity-70">
              "{c.user_note}"
            </p>

            <!-- Promoted info -->
            <div :if={c.status == "promoted"} class="mt-2 text-xs opacity-70">
              <p>
                {gettext("Promoted to")}
                <code class="font-mono">{c.promoted_to_path}</code>
                {gettext("by")} {c.promoted_by}
              </p>
              <p :if={c.corrected_answer}>
                {gettext("Correct answer:")} <span class="font-mono">{c.corrected_answer}</span>
              </p>
            </div>

            <p :if={c.status == "dismissed" and c.dismissed_reason}
               class="mt-2 text-xs opacity-70">
              {gettext("Dismissed:")} {c.dismissed_reason}
            </p>

            <!-- Action form (pending only) -->
            <div :if={c.status == "pending"} class="mt-3 space-y-2">
              <form phx-submit="promote" class="flex flex-col gap-2">
                <input type="hidden" name="candidate_id" value={c.id} />
                <textarea
                  name="corrected"
                  rows="2"
                  placeholder={gettext("What should the answer have contained? (substring match for final_answer_contains)")}
                  class="w-full rounded border border-base-300 bg-base-100 px-2 py-1 text-sm"
                >{c.corrected_answer}</textarea>
                <div class="flex flex-wrap items-center gap-2">
                  <button
                    type="submit"
                    class="px-5 py-1 text-xs font-medium"
                    style="background:#141413;color:#F3F0EE;border-radius:20px;"
                  >
                    {gettext("Promote to regressions")}
                  </button>
                  <span class="text-[11px] opacity-60">
                    {gettext("Adds one row to priv/eval/golden/regressions.jsonl")}
                  </span>
                </div>
              </form>

              <form phx-submit="dismiss" class="flex items-center gap-2">
                <input type="hidden" name="candidate_id" value={c.id} />
                <input
                  name="reason"
                  type="text"
                  placeholder={gettext("dismiss reason (optional)")}
                  class="flex-1 rounded-full border border-base-300 bg-base-100 px-3 py-1 text-xs"
                />
                <button
                  type="submit"
                  class="rounded-full border border-base-300 px-4 py-1 text-xs hover:bg-base-300/40"
                >
                  {gettext("Dismiss")}
                </button>
              </form>
            </div>
          </li>
        </ul>
      </div>
    </Layouts.app>
    """
  end

  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  defp format_time(_), do: "—"

  defp status_color("pending"), do: "bg-yellow-100 dark:bg-yellow-900/40 text-yellow-800 dark:text-yellow-200"
  defp status_color("promoted"), do: "bg-emerald-100 dark:bg-emerald-900/40 text-emerald-800 dark:text-emerald-200"
  defp status_color("dismissed"), do: "bg-base-300"
  defp status_color(_), do: "bg-base-200"
end
