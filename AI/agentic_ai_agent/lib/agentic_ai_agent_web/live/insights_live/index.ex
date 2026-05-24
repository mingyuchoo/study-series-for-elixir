defmodule AgenticAiAgentWeb.InsightsLive.Index do
  use AgenticAiAgentWeb, :live_view

  alias AgenticAiAgent.{Analytics, LLM.Pricing}

  @refresh_ms 30_000
  @periods ~w(7 30 90)

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(@refresh_ms, self(), :refresh)
    {:ok, socket |> assign(:days, 30) |> assign(:periods, @periods) |> load()}
  end

  @impl true
  def handle_event("select_period", %{"days" => days}, socket) do
    case Integer.parse(days || "") do
      {n, ""} when n > 0 -> {:noreply, socket |> assign(:days, n) |> load()}
      _ -> {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:refresh, socket), do: {:noreply, load(socket)}

  defp load(socket) do
    days = socket.assigns.days

    socket
    |> assign(:health, Analytics.run_health(days))
    |> assign(:failures, Analytics.failures_by_mode(days))
    |> assign(:tools, Analytics.tool_stats(days))
    |> assign(:skills, Analytics.skill_stats(days))
    |> assign(:skill_failures, index_by(Analytics.failures_by_skill(days), :skill_slug))
    |> assign(:daily, Analytics.daily_cost_quality(days))
    |> assign(:cards, Analytics.score_trend_per_card())
    |> assign(:regressions, Analytics.recent_regressions(days))
  end

  defp index_by(list, key), do: Map.new(list, fn item -> {Map.get(item, key), item} end)

  # ----- Render -----

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path={@current_path} locale={@locale}>
      <div class="space-y-6">
        <header class="flex items-baseline justify-between gap-3">
          <div>
            <div class="eyebrow mb-2">{gettext("Insights")}</div>
            <h1 class="text-2xl font-semibold">{gettext("Cross-run insights")}</h1>
            <p class="text-sm opacity-70">
              {gettext("Observability layer for self-improvement. Aggregates traces, failures, tool stats, and eval scores so you can see what's getting better or worse over time.")}
            </p>
          </div>
          <form phx-change="select_period">
            <label class="text-xs opacity-70" for="days">{gettext("Window")}</label>
            <select
              id="days"
              name="days"
              class="ml-2 rounded-full border border-base-300 bg-base-100 px-3 py-1 text-sm"
            >
              <option :for={d <- @periods} value={d} selected={Integer.parse(d) == {@days, ""}}>
                {d} {gettext("days")}
              </option>
            </select>
          </form>
        </header>

        <!-- Row 1: Run health summary -->
        <section class="rounded-lg border border-base-300 bg-base-200 p-4">
          <div class="mb-2 eyebrow">{gettext("Run health")}</div>
          <div class="grid grid-cols-2 gap-3 text-sm sm:grid-cols-5">
            <.stat label={gettext("Total runs")} value={@health.total} />
            <.stat
              label={gettext("Success rate")}
              value={format_pct(@health.success_rate)}
              accent={success_accent(@health.success_rate)}
            />
            <.stat
              label={gettext("Failed")}
              value={Map.get(@health.by_status, "failed", 0)}
              accent="text-red-700 dark:text-red-300"
            />
            <.stat
              label={gettext("Avg latency")}
              value={format_latency(@health.avg_latency_ms)}
            />
            <.stat
              label={gettext("Total cost")}
              value={Pricing.format(@health.total_cost_micro_usd)}
            />
          </div>
        </section>

        <!-- Row 2: Two-up — Top failures + Tool stats -->
        <div class="grid grid-cols-1 gap-4 lg:grid-cols-2">
          <section class="rounded-lg border border-base-300 bg-base-200 p-4">
            <div class="mb-2 eyebrow">{gettext("Top failure modes")}</div>
            <div :if={@failures == []} class="text-sm opacity-60">
              {gettext("No failures recorded in this window.")}
            </div>
            <table :if={@failures != []} class="w-full text-sm">
              <thead class="text-xs opacity-60">
                <tr class="text-left">
                  <th class="py-1">{gettext("Mode")}</th>
                  <th>{gettext("Severity")}</th>
                  <th class="text-right">{gettext("Count")}</th>
                  <th class="text-right">{gettext("Last seen")}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={f <- @failures} class="border-t border-base-300">
                  <td class="py-1.5">
                    <.link navigate={~p"/failures"} class="font-mono hover:underline">
                      {f.slug}
                    </.link>
                  </td>
                  <td>
                    <span class={["rounded px-2 py-0.5 text-[10px] font-mono uppercase", severity_color(f.severity)]}>
                      {f.severity}
                    </span>
                  </td>
                  <td class="text-right font-mono">{f.count}</td>
                  <td class="text-right text-xs opacity-70">{format_time(f.last_seen_at)}</td>
                </tr>
              </tbody>
            </table>
          </section>

          <section class="rounded-lg border border-base-300 bg-base-200 p-4">
            <div class="mb-2 eyebrow">{gettext("Tool usage")}</div>
            <div :if={@tools == []} class="text-sm opacity-60">
              {gettext("No tool calls in this window.")}
            </div>
            <table :if={@tools != []} class="w-full text-sm">
              <thead class="text-xs opacity-60">
                <tr class="text-left">
                  <th class="py-1">{gettext("Tool")}</th>
                  <th class="text-right">{gettext("Calls")}</th>
                  <th class="text-right">{gettext("Errors")}</th>
                  <th class="text-right">{gettext("Error rate")}</th>
                  <th class="text-right">{gettext("Avg ms")}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={t <- @tools} class="border-t border-base-300">
                  <td class="py-1.5 font-mono text-xs">{t.tool}</td>
                  <td class="text-right font-mono">{t.calls}</td>
                  <td class="text-right font-mono">{t.errors}</td>
                  <td class={["text-right font-mono", err_accent(t.error_rate)]}>
                    {format_pct(t.error_rate)}
                  </td>
                  <td class="text-right font-mono opacity-70">{format_latency(t.avg_latency_ms)}</td>
                </tr>
              </tbody>
            </table>
          </section>
        </div>

        <!-- Skills (sub-agent stats) -->
        <section :if={@skills != []} class="rounded-lg border border-base-300 bg-base-200 p-4">
          <div class="mb-2 eyebrow">{gettext("Skills (sub-agents)")}</div>
          <table class="w-full text-sm">
            <thead class="text-xs opacity-60">
              <tr class="text-left">
                <th class="py-1">{gettext("Skill")}</th>
                <th class="text-right">{gettext("Runs")}</th>
                <th class="text-right">{gettext("Success rate")}</th>
                <th class="text-right">{gettext("Failed")}</th>
                <th class="text-right">{gettext("Avg latency")}</th>
                <th>{gettext("Top failures")}</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={s <- @skills} class="border-t border-base-300">
                <td class="py-1.5 font-mono text-xs">{s.skill_slug}</td>
                <td class="text-right font-mono">{s.total}</td>
                <td class={["text-right font-mono", success_accent(s.success_rate)]}>
                  {format_pct(s.success_rate)}
                </td>
                <td class="text-right font-mono">{s.failed}</td>
                <td class="text-right font-mono opacity-70">{format_latency(s.avg_latency_ms)}</td>
                <td class="text-xs opacity-80">
                  <%= case Map.get(@skill_failures, s.skill_slug) do %>
                    <% nil -> %><span class="opacity-50">—</span>
                    <% sf -> %>
                      <span :for={m <- sf.by_mode} class="mr-2 font-mono text-[10px]">
                        {m.slug}×{m.count}
                      </span>
                  <% end %>
                </td>
              </tr>
            </tbody>
          </table>
        </section>

        <!-- Row 3: Daily cost + quality -->
        <section class="rounded-lg border border-base-300 bg-base-200 p-4">
          <div class="mb-2 eyebrow">{gettext("Daily volume")}</div>
          <div :if={@daily == []} class="text-sm opacity-60">
            {gettext("No data in this window.")}
          </div>
          <table :if={@daily != []} class="w-full text-sm">
            <thead class="text-xs opacity-60">
              <tr class="text-left">
                <th class="py-1">{gettext("Date")}</th>
                <th class="text-right">{gettext("Runs")}</th>
                <th class="text-right">{gettext("Cost")}</th>
                <th class="text-right">{gettext("Avg latency")}</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={d <- Enum.reverse(@daily)} class="border-t border-base-300">
                <td class="py-1.5 font-mono text-xs">{d.date}</td>
                <td class="text-right font-mono">{d.runs}</td>
                <td class="text-right font-mono">{Pricing.format(d.cost_micro_usd)}</td>
                <td class="text-right font-mono opacity-70">{format_latency(d.avg_latency_ms)}</td>
              </tr>
            </tbody>
          </table>
        </section>

        <!-- Row 4: Eval score per card -->
        <section class="rounded-lg border border-base-300 bg-base-200 p-4">
          <div class="mb-2 eyebrow">{gettext("Eval score per card")}</div>
          <div :if={@cards == []} class="text-sm opacity-60">
            {gettext("No eval runs yet. Trigger one from /evals.")}
          </div>
          <div :for={card <- @cards} class="mt-2">
            <div class="mb-1 flex items-baseline gap-2">
              <span class="font-mono text-xs opacity-70">{card.card_slug}</span>
              <span class="text-sm font-medium">{card.card_name}</span>
            </div>
            <table class="w-full text-sm">
              <thead class="text-xs opacity-60">
                <tr class="text-left">
                  <th class="py-1">{gettext("Date")}</th>
                  <th class="text-right">{gettext("Avg score")}</th>
                  <th class="text-right">{gettext("Threshold")}</th>
                  <th class="text-right">{gettext("Pass")}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={r <- card.runs} class="border-t border-base-300">
                  <td class="py-1.5 text-xs opacity-70">{format_time(r.finished_at)}</td>
                  <td class={["text-right font-mono", score_accent(r.average_score, r.pass_threshold)]}>
                    {format_score(r.average_score)}
                  </td>
                  <td class="text-right font-mono opacity-70">{format_score(r.pass_threshold)}</td>
                  <td class="text-right text-xs">
                    {r.passed_cases}/{r.total_cases}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>

        <!-- Row 5: Recent failed runs -->
        <section class="rounded-lg border border-base-300 bg-base-200 p-4">
          <div class="mb-2 eyebrow">{gettext("Recent regressions")}</div>
          <div :if={@regressions == []} class="text-sm opacity-60">
            {gettext("No failed runs in this window. Nothing to look at — that's good.")}
          </div>
          <ul :if={@regressions != []} class="space-y-2">
            <li :for={r <- @regressions} class="border-t border-base-300 pt-2 text-sm">
              <div class="flex items-baseline justify-between gap-2">
                <.link navigate={~p"/runs/#{r.id}"} class="font-mono text-xs hover:underline">
                  {String.slice(r.id, 0, 8)}
                </.link>
                <span class="text-xs opacity-60">{format_time(r.inserted_at)}</span>
              </div>
              <p class="mt-1 truncate text-xs opacity-80">{truncate(r.user_input, 200)}</p>
              <p :if={r.errors && r.errors != %{}} class="mt-0.5 truncate font-mono text-[10px] text-red-700 dark:text-red-300">
                {inspect(r.errors) |> String.slice(0, 200)}
              </p>
            </li>
          </ul>
        </section>
      </div>
    </Layouts.app>
    """
  end

  # ----- Small component -----

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :accent, :string, default: ""

  defp stat(assigns) do
    ~H"""
    <div class="rounded-md border border-base-300 bg-base-100 p-2">
      <div class="text-[10px] uppercase tracking-wider opacity-60">{@label}</div>
      <div class={["mt-0.5 font-mono text-lg", @accent]}>{@value}</div>
    </div>
    """
  end

  # ----- Formatters -----

  defp format_pct(n) when is_number(n), do: "#{Float.round(n * 100, 1)}%"
  defp format_pct(_), do: "—"

  defp format_latency(nil), do: "—"
  defp format_latency(ms) when is_number(ms) and ms < 1000, do: "#{round(ms)} ms"
  defp format_latency(ms) when is_number(ms), do: "#{Float.round(ms / 1000, 2)} s"

  defp format_score(nil), do: "—"
  defp format_score(n) when is_number(n), do: :io_lib.format("~5.3f", [n]) |> List.to_string()

  defp format_time(nil), do: "—"
  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")

  defp format_time(other) when is_binary(other), do: other
  defp format_time(_), do: "—"

  defp truncate(nil, _), do: ""

  defp truncate(text, n) when is_binary(text) do
    if String.length(text) > n, do: String.slice(text, 0, n) <> "…", else: text
  end

  defp success_accent(rate) when is_number(rate) and rate >= 0.9, do: "text-emerald-700 dark:text-emerald-300"
  defp success_accent(rate) when is_number(rate) and rate >= 0.7, do: ""
  defp success_accent(_), do: "text-red-700 dark:text-red-300"

  defp err_accent(rate) when is_number(rate) and rate >= 0.2, do: "text-red-700 dark:text-red-300"
  defp err_accent(_), do: ""

  defp score_accent(nil, _), do: "opacity-60"
  defp score_accent(_, nil), do: ""

  defp score_accent(s, t) when is_number(s) and is_number(t) and s >= t,
    do: "text-emerald-700 dark:text-emerald-300"

  defp score_accent(_, _), do: "text-red-700 dark:text-red-300"

  defp severity_color("critical"), do: "bg-red-100 dark:bg-red-900/40 text-red-800 dark:text-red-200"
  defp severity_color("high"), do: "bg-orange-100 dark:bg-orange-900/40 text-orange-800 dark:text-orange-200"
  defp severity_color("medium"), do: "bg-yellow-100 dark:bg-yellow-900/40 text-yellow-800 dark:text-yellow-200"
  defp severity_color("low"), do: "bg-blue-100 dark:bg-blue-900/40 text-blue-800 dark:text-blue-200"
  defp severity_color(_), do: "bg-base-300"
end
