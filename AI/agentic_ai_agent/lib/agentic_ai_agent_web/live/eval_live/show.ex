defmodule AgenticAiAgentWeb.EvalLive.Show do
  use AgenticAiAgentWeb, :live_view

  alias AgenticAiAgent.Eval

  @refresh_ms 3_000

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(AgenticAiAgent.PubSub, Eval.pubsub_topic())
      :timer.send_interval(@refresh_ms, self(), :tick)
    end

    {:ok, assign(socket, :eval_run, Eval.get_eval_run_with_cases!(id))}
  end

  @impl true
  def handle_info(:tick, %{assigns: %{eval_run: %{status: "running", id: id}}} = socket) do
    {:noreply, assign(socket, :eval_run, Eval.get_eval_run_with_cases!(id))}
  end

  def handle_info(:tick, socket), do: {:noreply, socket}

  def handle_info({:eval, :finished, {:ok, %{id: id}}}, %{assigns: %{eval_run: %{id: id}}} = socket) do
    {:noreply,
     socket
     |> put_flash(:info, gettext("Run finished."))
     |> assign(:eval_run, Eval.get_eval_run_with_cases!(id))}
  end

  def handle_info(_other, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path={@current_path} locale={@locale}>
      <div class="space-y-6">
        <header class="space-y-1">
          <.link navigate={~p"/evals"} class="text-sm opacity-70 hover:underline">&larr; {gettext("Evals")}</.link>
          <h1 class="font-mono text-lg">{String.slice(@eval_run.id, 0, 8)}</h1>
          <div class="flex items-center gap-2 text-xs">
            <span class={["rounded px-2 py-0.5 font-mono uppercase", status_color(@eval_run.status)]}>
              {@eval_run.status}
            </span>
            <span class="opacity-70">
              <b>{@eval_run.passed_cases}/{@eval_run.total_cases}</b> {gettext("passed · avg score")}
              <span class={[score_color(@eval_run.average_score, @eval_run.pass_threshold), "font-mono"]}>
                {format(@eval_run.average_score)}
              </span>
              · {gettext("threshold")} {format(@eval_run.pass_threshold)}
            </span>
          </div>
          <p class="font-mono text-xs opacity-50">{@eval_run.golden_path}</p>
        </header>

        <.section title={gettext("Rubric weights")}>
          <pre class="overflow-x-auto rounded bg-base-200 p-3 text-xs">{Jason.encode!(@eval_run.rubric || %{}, pretty: true)}</pre>
        </.section>

        <.section :if={@eval_run.summary} title={gettext("Summary")}>
          <pre class="overflow-x-auto rounded bg-base-200 p-3 text-xs">{Jason.encode!(@eval_run.summary, pretty: true)}</pre>
        </.section>

        <.section title={gettext("Cases")}>
          <ul class="space-y-2">
            <li :for={c <- @eval_run.cases} class={["rounded border p-3", if(c.passed, do: "border-emerald-300 dark:border-emerald-700", else: "border-red-300 dark:border-red-700")]}>
              <div class="flex items-baseline justify-between">
                <div>
                  <span class={["mr-2 inline-block", if(c.passed, do: "text-emerald-700 dark:text-emerald-200", else: "text-red-700 dark:text-red-200")]}>
                    {if c.passed, do: "✓", else: "✗"}
                  </span>
                  <span class="font-mono text-sm">{c.case_id}</span>
                  <span :if={c.task_type} class="ml-2 rounded bg-base-200 px-2 py-0.5 text-[10px]">{c.task_type}</span>
                </div>
                <div class="text-xs font-mono">
                  {gettext("total:")} <span class={score_color(c.total_score, @eval_run.pass_threshold)}>{format(c.total_score)}</span>
                </div>
              </div>

              <p class="mt-1 text-sm">{c.input}</p>

              <details class="mt-1">
                <summary class="cursor-pointer text-xs opacity-70">{gettext("scores")}</summary>
                <pre class="mt-1 overflow-x-auto rounded bg-base-200 p-2 text-xs">{Jason.encode!(c.scores || %{}, pretty: true)}</pre>
              </details>

              <details :if={c.expected} class="mt-1">
                <summary class="cursor-pointer text-xs opacity-70">{gettext("expected")}</summary>
                <pre class="mt-1 overflow-x-auto rounded bg-base-200 p-2 text-xs">{Jason.encode!(c.expected, pretty: true)}</pre>
                <p :if={c.expected_tools != []} class="mt-1 font-mono text-xs">
                  {gettext("expected_tools:")} {Enum.join(c.expected_tools, ", ")}
                </p>
              </details>

              <details :if={c.final_answer} class="mt-1">
                <summary class="cursor-pointer text-xs opacity-70">{gettext("final answer")}</summary>
                <pre class="mt-1 whitespace-pre-wrap rounded bg-base-200 p-2 text-xs">{c.final_answer}</pre>
              </details>

              <p :if={c.notes} class="mt-1 text-xs text-red-700 dark:text-red-200">{c.notes}</p>

              <p :if={c.run_id} class="mt-1 text-xs">
                <.link navigate={~p"/runs/#{c.run_id}"} class="font-mono opacity-70 hover:underline">
                  → {gettext("trace")} {String.slice(c.run_id, 0, 8)}
                </.link>
              </p>
            </li>
          </ul>
        </.section>
      </div>
    </Layouts.app>
    """
  end

  attr :title, :string, required: true
  slot :inner_block, required: true

  defp section(assigns) do
    ~H"""
    <section class="space-y-2">
      <h2 class="text-sm font-semibold uppercase tracking-wide opacity-70">{@title}</h2>
      <div>{render_slot(@inner_block)}</div>
    </section>
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
end
