defmodule AgenticAiAgentWeb.EvalLive.Index do
  use AgenticAiAgentWeb, :live_view

  alias AgenticAiAgent.Eval

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :runs, Eval.list_eval_runs(50))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path={@current_path} locale={@locale}>
      <div class="space-y-4">
        <header>
          <h1 class="text-2xl font-semibold">{gettext("Eval runs")}</h1>
          <p class="text-sm opacity-70">
            {gettext("Each run executes a golden dataset against an agentic card and scores every case with the heuristic rubric. Use mix agent.eval to launch one from the CLI.")}
          </p>
        </header>

        <div :if={@runs == []} class="rounded border border-dashed p-6 text-center text-sm opacity-70">
          {gettext("No eval runs yet. Try mix agent.eval.")}
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
