defmodule AgenticAiAgentWeb.RunLive.Show do
  use AgenticAiAgentWeb, :live_view

  alias AgenticAiAgent.Traces
  alias AgenticAiAgent.Agent.Runtime

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(AgenticAiAgent.PubSub, Runtime.topic(id))
    end

    {:ok, load(socket, id)}
  end

  @impl true
  def handle_info({:agent, _kind, _payload}, socket), do: {:noreply, refresh(socket)}
  def handle_info({:agent, _kind, _payload, _id}, socket), do: {:noreply, refresh(socket)}
  def handle_info(_other, socket), do: {:noreply, socket}

  @impl true
  def handle_event("delete_run", _params, socket) do
    short_id = String.slice(socket.assigns.run.id, 0, 8)
    _ = Traces.delete_run!(socket.assigns.run)

    {:noreply,
     socket
     |> put_flash(:info, gettext("Deleted run %{id}.", id: short_id))
     |> push_navigate(to: ~p"/runs")}
  end

  defp refresh(socket), do: load(socket, socket.assigns.run.id)

  defp load(socket, id) do
    run = Traces.get_run!(id)
    steps = Traces.list_steps(id)
    tool_calls = Traces.list_tool_calls(id)
    children = Traces.list_child_runs(id)
    approvals = Traces.list_approvals(id)

    socket
    |> assign(:run, run)
    |> assign(:steps, steps)
    |> assign(:tool_calls, index_by_step(tool_calls))
    |> assign(:children, children)
    |> assign(:approvals, approvals)
    |> assign(:totals, totals(steps, tool_calls))
  end

  defp index_by_step(tool_calls) do
    Enum.group_by(tool_calls, & &1.step_id)
  end

  defp totals(steps, tool_calls) do
    %{
      step_count: length(steps),
      tool_call_count: length(tool_calls),
      llm_call_count: Enum.count(steps, &(&1.kind == "llm_call")),
      total_step_latency_ms:
        steps
        |> Enum.map(&(&1.latency_ms || 0))
        |> Enum.sum()
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path={@current_path} locale={@locale}>
      <div class="space-y-6">
        <header class="space-y-1">
          <div class="flex items-baseline justify-between">
            <.link navigate={~p"/runs"} class="text-sm opacity-70 hover:underline">&larr; {gettext("Runs")}</.link>
            <button
              type="button"
              phx-click="delete_run"
              data-confirm={gettext("Delete this run? Steps, tool calls, and approvals are removed too. Linked eval cases keep their scores.")}
              class="rounded-full border border-base-300 px-3 py-1 text-[11px] font-medium text-base-content/70 hover:bg-base-300/40"
            >
              {gettext("Delete run")}
            </button>
          </div>
          <h1 class="font-mono text-lg">{String.slice(@run.id, 0, 8)}</h1>
          <div class="flex items-center gap-2 text-xs">
            <span class={["rounded px-2 py-0.5 font-mono uppercase", status_color(@run.status)]}>
              {@run.status}
            </span>
            <span
              :if={@run.workflow_state}
              class="rounded border border-base-300 px-2 py-0.5 font-mono text-[10px] uppercase opacity-80"
              title={gettext("workflow state")}
            >
              ⛬ {@run.workflow_state}
            </span>
            <span class="opacity-70">
              {format_latency(@run.latency_ms)} ·
              {@totals.llm_call_count} {gettext("LLM")} · {@totals.tool_call_count} {gettext("tool")} ·
              {@totals.step_count} {gettext("steps")} ·
              <span class="font-mono">{format_cost(@run.cost_micro_usd)}</span>
              <span :if={(@run.prompt_tokens || 0) + (@run.completion_tokens || 0) > 0} class="opacity-60">
                ({@run.prompt_tokens || 0}↑ / {@run.completion_tokens || 0}↓ {gettext("tokens")})
              </span>
            </span>
          </div>
        </header>

        <.section title={gettext("User input")}>
          <pre class="whitespace-pre-wrap rounded bg-base-200 p-3 text-sm">{@run.user_input}</pre>
        </.section>

        <.section :if={@run.final_answer} title={gettext("Final answer")}>
          <pre class="whitespace-pre-wrap rounded bg-emerald-50 dark:bg-emerald-950/40 p-3 text-sm">{@run.final_answer}</pre>
        </.section>

        <.section :if={@run.errors} title={gettext("Errors")}>
          <pre class="overflow-x-auto rounded bg-red-50 dark:bg-red-950/40 p-3 text-xs">{Jason.encode!(@run.errors, pretty: true)}</pre>
        </.section>

        <.section :if={@run.parent_run_id} title={gettext("Parent run")}>
          <.link navigate={~p"/runs/#{@run.parent_run_id}"} class="font-mono text-sm hover:underline">
            {String.slice(@run.parent_run_id, 0, 8)}
          </.link>
          <span :if={@run.skill_slug} class="ml-2 rounded bg-violet-100 dark:bg-violet-900/40 px-2 py-0.5 text-xs">
            {gettext("skill:")} {@run.skill_slug}
          </span>
        </.section>

        <.section :if={@children != []} title={gettext("Sub-agents")}>
          <ul class="space-y-1">
            <li :for={c <- @children} class="flex items-center gap-2 text-sm">
              <.link navigate={~p"/runs/#{c.id}"} class="font-mono hover:underline">
                {String.slice(c.id, 0, 8)}
              </.link>
              <span class={["rounded px-2 py-0.5 text-[10px] font-mono uppercase", status_color(c.status)]}>
                {c.status}
              </span>
              <span :if={c.skill_slug} class="rounded bg-violet-100 dark:bg-violet-900/40 px-2 py-0.5 text-[10px]">
                {gettext("skill:")} {c.skill_slug}
              </span>
              <span class="text-xs opacity-70">{truncate(c.user_input, 60)}</span>
            </li>
          </ul>
        </.section>

        <.section :if={@approvals != []} title={gettext("HITL approvals")}>
          <ul class="space-y-1">
            <li :for={a <- @approvals} class="rounded border p-2 text-sm">
              <div class="flex items-center justify-between">
                <span class="font-mono text-xs">{a.tool_name}</span>
                <span class={["rounded px-2 py-0.5 text-[10px] font-mono uppercase", approval_color(a.status)]}>
                  {a.status}
                </span>
              </div>
              <pre class="mt-1 overflow-x-auto rounded bg-base-200 p-2 text-xs">{Jason.encode!(a.input || %{}, pretty: true)}</pre>
              <p :if={a.notes} class="mt-1 text-xs opacity-70">{gettext("notes:")} {a.notes}</p>
              <p :if={a.decided_by} class="text-xs opacity-50">
                {gettext("decided by %{by} at %{at}", by: a.decided_by, at: to_string(a.decided_at))}
              </p>
            </li>
          </ul>
        </.section>

        <.section title={gettext("Timeline")}>
          <ol class="space-y-2">
            <li :for={step <- @steps} class={["rounded border p-3", step_color(step.kind)]}>
              <div class="mb-1 flex items-baseline justify-between">
                <div class="flex items-center gap-2">
                  <span class="font-mono text-xs opacity-60">#{step.idx}</span>
                  <span class="rounded bg-base-100/60 px-2 py-0.5 font-mono text-[10px] uppercase">
                    {step.kind}
                  </span>
                  <span :if={step.model} class="font-mono text-[10px] opacity-50">{step.model}</span>
                </div>
                <div class="flex items-center gap-2 text-xs opacity-60">
                  <span :if={step.cost_micro_usd} class="font-mono">{format_cost(step.cost_micro_usd)}</span>
                  <span>{format_latency(step.latency_ms)}</span>
                </div>
              </div>

              <.step_payload step={step} tool_calls={Map.get(@tool_calls, step.id, [])} />
            </li>
          </ol>
        </.section>
      </div>
    </Layouts.app>
    """
  end

  # ----- Components -----

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

  attr :step, :map, required: true
  attr :tool_calls, :list, default: []

  defp step_payload(%{step: %{kind: "llm_call", payload: payload}} = assigns) do
    assigns = assign(assigns, :payload, payload || %{})

    ~H"""
    <div class="space-y-1 text-sm">
      <div :if={@payload["content"]} class="whitespace-pre-wrap">{@payload["content"]}</div>
      <div :if={@payload["tool_calls"] && @payload["tool_calls"] != []} class="space-y-1">
        <div class="font-mono text-xs opacity-60">{gettext("requested tool calls:")}</div>
        <ul class="space-y-1">
          <li :for={tc <- @payload["tool_calls"]} class="font-mono text-xs">
            → {tool_name(tc)}({Jason.encode!(tool_args(tc))})
          </li>
        </ul>
      </div>
      <div :if={@payload["finish_reason"]} class="text-[10px] font-mono opacity-50">
        finish_reason: {@payload["finish_reason"]}
      </div>
      <div :if={@payload["usage"]} class="text-[10px] font-mono opacity-50">
        usage: {Jason.encode!(@payload["usage"])}
      </div>
    </div>
    """
  end

  defp step_payload(%{step: %{kind: "tool_call", payload: payload}} = assigns) do
    assigns = assign(assigns, :payload, payload || %{})

    ~H"""
    <div class="space-y-1 text-sm">
      <div class="font-mono text-xs">{@payload["name"]}</div>
      <details>
        <summary class="cursor-pointer text-xs opacity-70">{gettext("input")}</summary>
        <pre class="mt-1 overflow-x-auto rounded bg-base-100/60 p-2 text-xs">{Jason.encode!(@payload["input"] || %{}, pretty: true)}</pre>
      </details>
      <details :if={@payload["output"]} open>
        <summary class="cursor-pointer text-xs opacity-70">{gettext("output")}</summary>
        <pre class="mt-1 overflow-x-auto rounded bg-base-100/60 p-2 text-xs">{Jason.encode!(@payload["output"], pretty: true)}</pre>
      </details>
      <div :if={@payload["error"]} class="rounded bg-red-100 dark:bg-red-900/40 p-2 text-xs text-red-700 dark:text-red-200">
        {gettext("error:")} {@payload["error"]}
      </div>
    </div>
    """
  end

  defp step_payload(%{step: %{kind: "reflect", payload: payload}} = assigns) do
    assigns = assign(assigns, :payload, payload || %{})

    ~H"""
    <div :if={@payload["critique"]} class="space-y-1 text-sm">
      <div class="font-mono text-xs opacity-60">
        {gettext("self-critique")} (#{@payload["reflexion_count"]})
      </div>
      <pre class="whitespace-pre-wrap rounded bg-base-100 dark:bg-base-300 p-2 text-sm">{@payload["critique"]}</pre>
    </div>
    <pre :if={!@payload["critique"]} class="overflow-x-auto rounded bg-base-200 p-2 text-xs">{Jason.encode!(@payload, pretty: true)}</pre>
    """
  end

  defp step_payload(%{step: %{kind: "plan", payload: %{"strategy" => "tot"} = payload}} = assigns) do
    assigns =
      assigns
      |> assign(:payload, payload)
      |> assign(:candidates, payload["candidates"] || [])
      |> assign(:chosen, payload["chosen"])

    ~H"""
    <div class="space-y-2 text-sm">
      <div class="font-mono text-xs opacity-60">
        {gettext("Tree of Thoughts — %{n} candidates", n: length(@candidates))}
      </div>
      <ul class="space-y-1">
        <li :for={c <- @candidates}
            class={["rounded border p-2 text-xs",
                    if(@chosen && c["plan"] == @chosen["plan"],
                      do: "border-emerald-400 dark:border-emerald-600 bg-emerald-50 dark:bg-emerald-950/40",
                      else: "bg-base-100 dark:bg-base-300")]}>
          <div class="flex items-baseline justify-between">
            <span class="font-mono">{gettext("score:")} {c["score"]}</span>
            <span :if={@chosen && c["plan"] == @chosen["plan"]} class="rounded bg-emerald-200 dark:bg-emerald-800 px-2 py-0.5 text-[10px]">
              {gettext("chosen")}
            </span>
          </div>
          <p class="mt-1 whitespace-pre-wrap">{c["plan"]}</p>
          <p :if={c["rationale"]} class="mt-1 opacity-70">{c["rationale"]}</p>
        </li>
      </ul>
    </div>
    """
  end

  defp step_payload(%{step: %{kind: "retrieve", payload: payload}} = assigns) do
    assigns =
      assigns
      |> assign(:payload, payload || %{})
      |> assign(:matches, (payload && payload["matches"]) || [])

    ~H"""
    <div class="space-y-1 text-sm">
      <div class="font-mono text-xs opacity-60">
        {gettext("retrieved")} {length(@matches)} {gettext("memory matches for query:")}
      </div>
      <p class="font-mono text-xs opacity-70">{truncate(@payload["query"], 200)}</p>
      <ul :if={@matches != []} class="space-y-1">
        <li :for={m <- @matches} class="rounded border bg-base-100 dark:bg-base-300 p-2 text-xs">
          <div class="flex justify-between font-mono opacity-60">
            <span>{m["kind"]}/{m["source"] || "—"}</span>
            <span>{gettext("score:")} {m["score"]}</span>
          </div>
          <p class="mt-1 whitespace-pre-wrap">{m["content_preview"]}</p>
        </li>
      </ul>
    </div>
    """
  end

  defp step_payload(%{step: %{kind: "steer", payload: payload}} = assigns) do
    assigns = assign(assigns, :payload, payload || %{})

    ~H"""
    <div class="space-y-1 text-sm">
      <div class="font-mono text-xs opacity-60">{gettext("user steering guidance:")}</div>
      <pre class="whitespace-pre-wrap rounded bg-base-100 dark:bg-base-300 p-2 text-sm">{@payload["guidance"]}</pre>
    </div>
    """
  end

  defp step_payload(%{step: %{kind: "delegate", payload: payload}} = assigns) do
    assigns = assign(assigns, :payload, payload || %{})

    ~H"""
    <div class="space-y-1 text-sm">
      <div class="font-mono text-xs">
        {gettext("delegated to sub-agent")}
        <span :if={@payload["skill"]} class="rounded bg-violet-200 px-1">{gettext("skill:")} {@payload["skill"]}</span>
      </div>
      <p class="text-sm">{@payload["task"]}</p>
      <p :if={@payload["sub_run_id"]} class="text-xs">
        <.link navigate={~p"/runs/#{@payload["sub_run_id"]}"} class="font-mono hover:underline">
          → {String.slice(@payload["sub_run_id"], 0, 8)}
        </.link>
      </p>
    </div>
    """
  end

  defp step_payload(%{step: %{kind: "final", payload: payload}} = assigns) do
    assigns = assign(assigns, :payload, payload || %{})

    ~H"""
    <pre class="whitespace-pre-wrap text-sm">{@payload["content"]}</pre>
    """
  end

  defp step_payload(%{step: %{payload: payload}} = assigns) do
    assigns = assign(assigns, :payload, payload || %{})

    ~H"""
    <pre class="overflow-x-auto rounded bg-base-100/60 p-2 text-xs">{Jason.encode!(@payload, pretty: true)}</pre>
    """
  end

  # ----- Helpers -----

  defp tool_name(%{"function" => %{"name" => n}}), do: n
  defp tool_name(%{name: n}), do: n
  defp tool_name(_), do: "?"

  defp tool_args(%{"function" => %{"arguments" => args}}) when is_binary(args) do
    case Jason.decode(args) do
      {:ok, decoded} -> decoded
      _ -> %{"_raw" => args}
    end
  end

  defp tool_args(%{arguments: args}), do: args
  defp tool_args(_), do: %{}

  defp step_color("llm_call"), do: "border-slate-300 dark:border-slate-700 bg-slate-50 dark:bg-slate-950/40"
  defp step_color("tool_call"), do: "border-amber-300 dark:border-amber-700 bg-amber-50 dark:bg-amber-950/40"
  defp step_color("delegate"), do: "border-violet-300 dark:border-violet-700 bg-violet-50 dark:bg-violet-950/40"
  defp step_color("steer"), do: "border-amber-400 dark:border-amber-600 bg-amber-100 dark:bg-amber-900/40"
  defp step_color("retrieve"), do: "border-cyan-300 dark:border-cyan-700 bg-cyan-50 dark:bg-cyan-950/40"
  defp step_color("reflect"), do: "border-fuchsia-300 dark:border-fuchsia-700 bg-fuchsia-50 dark:bg-fuchsia-950/40"
  defp step_color("plan"), do: "border-indigo-300 dark:border-indigo-700 bg-indigo-50 dark:bg-indigo-950/40"
  defp step_color("final"), do: "border-emerald-300 dark:border-emerald-700 bg-emerald-50 dark:bg-emerald-950/40"
  defp step_color(_), do: "border-gray-300 bg-gray-50"

  defp approval_color("approved"), do: "bg-emerald-100 dark:bg-emerald-900/40 text-emerald-800 dark:text-emerald-200"
  defp approval_color("denied"), do: "bg-red-100 dark:bg-red-900/40 text-red-800 dark:text-red-200"
  defp approval_color("revised"), do: "bg-amber-100 dark:bg-amber-900/40 text-amber-800 dark:text-amber-200"
  defp approval_color("pending"), do: "bg-yellow-100 dark:bg-yellow-900/40 text-yellow-800 dark:text-yellow-200"
  defp approval_color(_), do: "bg-gray-100 text-gray-800"

  defp truncate(nil, _n), do: ""

  defp truncate(text, n) when is_binary(text) do
    if String.length(text) > n, do: String.slice(text, 0, n) <> "…", else: text
  end

  defp status_color("done"), do: "bg-green-100 dark:bg-green-900/40 text-green-800 dark:text-green-200"
  defp status_color("failed"), do: "bg-red-100 dark:bg-red-900/40 text-red-800 dark:text-red-200"
  defp status_color("running"), do: "bg-yellow-100 dark:bg-yellow-900/40 text-yellow-800 dark:text-yellow-200"
  defp status_color("awaiting_approval"), do: "bg-orange-100 dark:bg-orange-900/40 text-orange-800 dark:text-orange-200"
  defp status_color("cancelled"), do: "bg-base-300 text-base-content"
  defp status_color(_), do: "bg-gray-100 text-gray-800"

  defp format_latency(nil), do: "—"
  defp format_latency(ms) when ms < 1000, do: "#{ms} ms"
  defp format_latency(ms), do: "#{Float.round(ms / 1000, 2)} s"

  defp format_cost(nil), do: "—"
  defp format_cost(n) when is_integer(n), do: AgenticAiAgent.LLM.Pricing.format(n)
end
