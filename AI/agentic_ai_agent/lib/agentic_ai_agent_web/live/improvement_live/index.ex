defmodule AgenticAiAgentWeb.ImprovementLive.Index do
  use AgenticAiAgentWeb, :live_view

  alias AgenticAiAgent.{Design, Improver}
  alias AgenticAiAgentWeb.Diff

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(AgenticAiAgent.PubSub, AgenticAiAgent.Eval.pubsub_topic())
    end

    cards = Design.list_cards()
    default_slug = (List.first(cards) || %{}) |> Map.get(:slug)

    {:ok,
     socket
     |> assign(:cards, cards)
     |> assign(:slug, default_slug)
     |> assign(:generating?, false)
     |> assign(:status_filter, "all")
     |> assign(:expanded_id, nil)
     |> load_proposals()}
  end

  # ----- Events -----

  @impl true
  def handle_event("select_card", %{"slug" => slug}, socket),
    do: {:noreply, assign(socket, :slug, slug)}

  def handle_event("filter", %{"status" => status}, socket),
    do: {:noreply, socket |> assign(:status_filter, status) |> load_proposals()}

  def handle_event("expand", %{"id" => id}, socket) do
    toggled = if socket.assigns.expanded_id == id, do: nil, else: id
    {:noreply, assign(socket, :expanded_id, toggled)}
  end

  def handle_event("generate", _params, %{assigns: %{slug: nil}} = socket),
    do: {:noreply, put_flash(socket, :error, gettext("Pick a card first."))}

  def handle_event("generate", _params, socket) do
    parent = self()
    slug = socket.assigns.slug

    Task.Supervisor.start_child(AgenticAiAgent.Tools.TaskSupervisor, fn ->
      result = Improver.generate_proposal(slug)
      send(parent, {:improver_done, result})
    end)

    {:noreply,
     socket
     |> assign(:generating?, true)
     |> put_flash(:info, gettext("Asking the improver for a proposal on card %{slug}…", slug: slug))}
  end

  def handle_event("approve", %{"id" => id}, socket) do
    _ = Improver.approve!(Improver.get_proposal!(id), "hitl-user")
    {:noreply, socket |> put_flash(:info, gettext("Proposal approved.")) |> load_proposals()}
  end

  def handle_event("reject", %{"proposal_id" => id, "reason" => reason}, socket) do
    _ = Improver.reject!(Improver.get_proposal!(id), "hitl-user", reason || "")
    {:noreply, socket |> put_flash(:info, gettext("Proposal rejected.")) |> load_proposals()}
  end

  def handle_event("apply", %{"id" => id}, socket) do
    p = Improver.get_proposal!(id)

    case Improver.apply!(p, "hitl-user") do
      %_{status: "applied"} = applied ->
        flash =
          gettext("Applied proposal — card %{target} updated. A new version row was created.",
            target: applied.target
          )

        {:noreply, socket |> put_flash(:info, flash) |> load_proposals()}

      %_{status: "failed", apply_error: err} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Apply failed: %{e}", e: err))
         |> load_proposals()}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Apply refused: %{r}", r: inspect(reason)))
         |> load_proposals()}
    end
  end

  def handle_event("stage", %{"id" => id}, socket) do
    p = Improver.get_proposal!(id)

    case Improver.stage!(p, "hitl-user") do
      %_{status: "staging"} = staged ->
        msg =
          gettext("Staging started on %{slug}. Eval will run and the delta will appear here.",
            slug: staged.staging_slug
          )

        {:noreply, socket |> put_flash(:info, msg) |> load_proposals()}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Stage failed: %{r}", r: inspect(reason)))
         |> load_proposals()}
    end
  end

  def handle_event("discard_staging", %{"id" => id}, socket) do
    p = Improver.get_proposal!(id)
    _ = Improver.discard_staging!(p, "hitl-user")

    {:noreply,
     socket
     |> put_flash(:info, gettext("Staging card discarded. Proposal returned to approved."))
     |> load_proposals()}
  end

  # ----- Messages -----

  @impl true
  def handle_info({:improver_done, {:ok, proposal}}, socket) do
    msg =
      case proposal.status do
        "pending" -> gettext("New proposal awaiting review.")
        "rejected" -> gettext("Improver returned noop (no useful change found).")
        "malformed" -> gettext("LLM response could not be parsed; row stored for inspection.")
        _ -> gettext("Improver finished.")
      end

    {:noreply, socket |> assign(:generating?, false) |> put_flash(:info, msg) |> load_proposals()}
  end

  def handle_info({:improver_done, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:generating?, false)
     |> put_flash(:error, gettext("Generation failed: %{r}", r: inspect(reason)))}
  end

  # An eval somewhere finished; if it was one of our staging runs the
  # Improver.Staging GenServer has already updated the row. Just refresh.
  def handle_info({:eval, _kind, _payload}, socket) do
    {:noreply, load_proposals(socket)}
  end

  def handle_info(_other, socket), do: {:noreply, socket}

  # ----- Data -----

  defp load_proposals(socket) do
    status = if socket.assigns.status_filter == "all", do: nil, else: socket.assigns.status_filter
    assign(socket, :proposals, Improver.list_proposals(status: status))
  end

  defp current_yaml(slug) do
    case Design.card_source_path(slug) do
      nil -> ""
      path -> File.read!(path)
    end
  rescue
    _ -> ""
  end

  # ----- Render -----

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path={@current_path} locale={@locale}>
      <div class="space-y-6">
        <header class="flex items-baseline justify-between gap-3">
          <div>
            <div class="eyebrow mb-2">{gettext("Improvements")}</div>
            <h1 class="text-2xl font-semibold">{gettext("Improvement proposals")}</h1>
            <p class="text-sm opacity-70">
              {gettext("The meta-agent reads recent failures and eval trends, then proposes ONE focused YAML edit at a time. Nothing is auto-applied — you approve, then apply.")}
            </p>
          </div>
        </header>

        <!-- Generate panel -->
        <section class="rounded-lg border border-base-300 bg-base-200 p-4">
          <div class="mb-2 eyebrow">{gettext("Ask the improver")}</div>
          <div class="flex flex-wrap items-center gap-3 text-sm">
            <label class="text-xs opacity-70" for="card_slug">{gettext("Card")}</label>
            <select
              id="card_slug"
              phx-change="select_card"
              name="slug"
              class="rounded-full border border-base-300 bg-base-100 px-3 py-1 text-sm"
              disabled={@generating?}
            >
              <option :for={c <- @cards} value={c.slug} selected={c.slug == @slug}>
                {c.name} ({c.slug})
              </option>
            </select>
            <button
              type="button"
              phx-click="generate"
              disabled={@generating? or @slug == nil}
              class="px-5 py-1.5 text-sm font-medium disabled:opacity-50"
              style="background:#141413;color:#F3F0EE;border-radius:20px;letter-spacing:-0.02em;"
            >
              {if @generating?, do: gettext("Generating…"), else: gettext("Generate proposal")}
            </button>
            <span class="ml-auto text-[11px] opacity-60">
              {gettext("Uses one LLM call. Result lands in the queue below.")}
            </span>
          </div>
        </section>

        <!-- Filter -->
        <form phx-change="filter" class="flex flex-wrap items-center gap-2 text-xs">
          <span class="eyebrow">{gettext("Filter")}</span>
          <select name="status" class="rounded-full border border-base-300 bg-base-100 px-3 py-1">
            <option :for={s <- ~w(all pending approved staging staged_passed staged_failed applied rejected failed malformed rolled_back)} value={s} selected={s == @status_filter}>
              {s}
            </option>
          </select>
          <span class="opacity-60">{length(@proposals)} {gettext("shown")}</span>
        </form>

        <!-- Queue -->
        <div :if={@proposals == []} class="rounded border border-dashed p-6 text-center text-sm opacity-70">
          {gettext("No proposals match this filter.")}
        </div>

        <ul :if={@proposals != []} class="space-y-3">
          <li :for={p <- @proposals} class="rounded-lg border border-base-300 bg-base-200 p-3">
            <div class="flex flex-wrap items-baseline justify-between gap-2">
              <div class="flex items-baseline gap-2">
                <button
                  type="button"
                  phx-click="expand"
                  phx-value-id={p.id}
                  class="font-mono text-xs underline-offset-2 hover:underline"
                >
                  {Design.short_sha(p.id)}
                </button>
                <span class="font-mono text-[10px] uppercase opacity-60">{p.kind}</span>
                <span class={["rounded px-2 py-0.5 text-[10px] font-mono uppercase", status_color(p.status)]}>
                  {p.status}
                </span>
                <span :if={p.auto_promoted} class="rounded bg-purple-100 dark:bg-purple-900/40 text-purple-800 dark:text-purple-200 px-2 py-0.5 text-[10px] font-mono uppercase">
                  🤖 {gettext("auto")}
                </span>
                <span :if={p.rolled_back_at} class="rounded bg-red-100 dark:bg-red-900/40 text-red-800 dark:text-red-200 px-2 py-0.5 text-[10px] font-mono uppercase">
                  ⤺ {gettext("rolled back")}
                </span>
                <code class="font-mono text-xs opacity-70">→ {p.target}</code>
              </div>
              <span class="text-xs opacity-60">{format_time(p.inserted_at)}</span>
            </div>

            <p :if={p.rolled_back_reason} class="mt-1 font-mono text-xs text-red-700 dark:text-red-300">
              ⤺ {p.rolled_back_reason}
              <span :if={p.rolled_back_at} class="opacity-70"> · {format_time(p.rolled_back_at)}</span>
            </p>

            <p :if={p.justification} class="mt-2 text-sm">{p.justification}</p>

            <p :if={p.expected_score_delta} class="mt-1 font-mono text-xs opacity-70">
              {gettext("expected Δscore:")} {format_delta(p.expected_score_delta)}
            </p>

            <p :if={p.supporting_run_ids != []} class="mt-1 text-xs">
              {gettext("supporting runs:")}
              <span :for={rid <- p.supporting_run_ids} class="ml-1">
                <.link navigate={~p"/runs/#{rid}"} class="font-mono opacity-70 hover:underline">
                  {String.slice(rid, 0, 8)}
                </.link>
              </span>
            </p>

            <p :if={p.decision_reason} class="mt-1 text-xs opacity-70">
              {gettext("decision:")} {p.decision_reason}
            </p>

            <p :if={p.apply_error} class="mt-1 font-mono text-xs text-red-700 dark:text-red-300">
              {p.apply_error}
            </p>

            <!-- Expanded diff -->
            <div :if={@expanded_id == p.id and p.kind == "card_edit" and p.proposed_body} class="mt-3 space-y-2">
              <div class="eyebrow">{gettext("Diff: current → proposed")}</div>
              <.diff_view from={current_yaml(p.target)} to={p.proposed_body} />
            </div>

            <!-- Staging info (when present) -->
            <div :if={p.staging_slug} class="mt-2 rounded border border-base-300 bg-base-100 p-2 text-xs">
              <div class="flex flex-wrap items-baseline gap-3">
                <span class="font-mono opacity-70">
                  {gettext("staging:")} <code>{p.staging_slug}</code>
                </span>
                <span :if={p.baseline_score} class="font-mono opacity-70">
                  {gettext("baseline:")} {format_score(p.baseline_score)}
                </span>
                <span :if={p.staging_score} class="font-mono opacity-70">
                  {gettext("staging:")} {format_score(p.staging_score)}
                </span>
                <span :if={p.score_delta != nil} class={["font-mono font-semibold", delta_color(p.score_delta)]}>
                  Δ {format_delta(p.score_delta)}
                </span>
                <span :if={p.staging_eval_run_id} class="ml-auto">
                  <.link navigate={~p"/evals/#{p.staging_eval_run_id}"} class="opacity-70 hover:underline">
                    {gettext("→ staging eval")}
                  </.link>
                </span>
              </div>
            </div>

            <!-- Action row -->
            <div class="mt-3 flex flex-wrap items-center gap-2">
              <button
                :if={p.status == "pending"}
                type="button"
                phx-click="approve"
                phx-value-id={p.id}
                class="rounded-full border border-base-300 px-4 py-1 text-xs hover:bg-base-300/40"
              >
                {gettext("Approve")}
              </button>

              <form
                :if={p.status == "pending"}
                phx-submit="reject"
                class="flex items-center gap-2"
              >
                <input type="hidden" name="proposal_id" value={p.id} />
                <input
                  name="reason"
                  type="text"
                  placeholder={gettext("reason (optional)")}
                  class="rounded-full border border-base-300 bg-base-100 px-3 py-1 text-xs"
                />
                <button
                  type="submit"
                  class="rounded-full border border-red-400 dark:border-red-600 px-4 py-1 text-xs text-red-700 dark:text-red-200 hover:bg-red-50 dark:hover:bg-red-950/40"
                >
                  {gettext("Reject")}
                </button>
              </form>

              <!-- Approved: can either Stage (eval-gated) or Apply directly -->
              <button
                :if={p.status == "approved"}
                type="button"
                phx-click="stage"
                phx-value-id={p.id}
                class="rounded-full border border-base-300 px-4 py-1 text-xs hover:bg-base-300/40"
              >
                {gettext("Stage & Eval")}
              </button>

              <button
                :if={p.status == "approved"}
                type="button"
                phx-click="apply"
                phx-value-id={p.id}
                data-confirm={gettext("Apply this proposal to %{target} WITHOUT staging? Phase 2 versioning will snapshot the current state first.", target: p.target)}
                class="rounded-full border border-base-300 px-4 py-1 text-xs hover:bg-base-300/40"
              >
                {gettext("Apply without staging")}
              </button>

              <!-- Staging in progress -->
              <span :if={p.status == "staging"} class="text-xs text-amber-700 dark:text-amber-300">
                ⟳ {gettext("Staging eval running…")}
              </span>

              <!-- Staged passed: prominent Apply button -->
              <button
                :if={p.status == "staged_passed"}
                type="button"
                phx-click="apply"
                phx-value-id={p.id}
                data-confirm={gettext("Apply this proposal? Delta = %{d}.", d: format_delta(p.score_delta))}
                class="px-5 py-1 text-xs font-medium"
                style="background:#141413;color:#F3F0EE;border-radius:20px;"
              >
                {gettext("Promote (apply)")}
              </button>

              <!-- Staged failed: still applyable but with a stronger confirm -->
              <button
                :if={p.status == "staged_failed"}
                type="button"
                phx-click="apply"
                phx-value-id={p.id}
                data-confirm={gettext("Staging eval did WORSE (Δ %{d}). Apply anyway?", d: format_delta(p.score_delta))}
                class="rounded-full border border-red-400 dark:border-red-600 px-4 py-1 text-xs text-red-700 dark:text-red-200 hover:bg-red-50 dark:hover:bg-red-950/40"
              >
                {gettext("Apply anyway")}
              </button>

              <!-- Discard staging — always available while staging slug exists -->
              <button
                :if={p.staging_slug and p.status in ["staging", "staged_passed", "staged_failed"]}
                type="button"
                phx-click="discard_staging"
                phx-value-id={p.id}
                class="rounded-full border border-base-300 px-4 py-1 text-xs hover:bg-base-300/40"
              >
                {gettext("Discard staging")}
              </button>

              <.link
                :if={p.kind == "card_edit"}
                navigate={~p"/cards/#{find_card_id(p.target, @cards)}/history"}
                class="ml-auto text-[11px] opacity-70 hover:underline"
              >
                {gettext("Open target's history →")}
              </.link>
            </div>
          </li>
        </ul>
      </div>
    </Layouts.app>
    """
  end

  # ----- Component -----

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

  # ----- Formatters -----

  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  defp format_time(_), do: "—"

  defp format_delta(n) when is_number(n) and n >= 0, do: "+#{Float.round(n, 3)}"
  defp format_delta(n) when is_number(n), do: "#{Float.round(n, 3)}"
  defp format_delta(_), do: "—"

  defp format_score(n) when is_number(n), do: :io_lib.format("~5.3f", [n]) |> List.to_string()
  defp format_score(_), do: "—"

  defp delta_color(n) when is_number(n) and n > 0, do: "text-emerald-700 dark:text-emerald-300"
  defp delta_color(n) when is_number(n) and n < 0, do: "text-red-700 dark:text-red-300"
  defp delta_color(_), do: ""

  defp find_card_id(slug, cards) do
    case Enum.find(cards, &(&1.slug == slug)) do
      nil -> ""
      c -> c.id
    end
  end

  defp status_color("pending"), do: "bg-yellow-100 dark:bg-yellow-900/40 text-yellow-800 dark:text-yellow-200"
  defp status_color("approved"), do: "bg-blue-100 dark:bg-blue-900/40 text-blue-800 dark:text-blue-200"
  defp status_color("staging"), do: "bg-amber-100 dark:bg-amber-900/40 text-amber-800 dark:text-amber-200"
  defp status_color("staged_passed"), do: "bg-emerald-100 dark:bg-emerald-900/40 text-emerald-800 dark:text-emerald-200"
  defp status_color("staged_failed"), do: "bg-red-100 dark:bg-red-900/40 text-red-800 dark:text-red-200"
  defp status_color("applied"), do: "bg-green-100 dark:bg-green-900/40 text-green-800 dark:text-green-200"
  defp status_color("rejected"), do: "bg-base-300"
  defp status_color("failed"), do: "bg-red-100 dark:bg-red-900/40 text-red-800 dark:text-red-200"
  defp status_color("malformed"), do: "bg-orange-100 dark:bg-orange-900/40 text-orange-800 dark:text-orange-200"
  defp status_color(_), do: "bg-base-200"
end
