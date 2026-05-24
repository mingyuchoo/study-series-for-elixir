defmodule AgenticAiAgentWeb.HomeLive do
  @moduledoc """
  Landing page. A small dashboard that:

    * Surfaces the status of the configured LLM adapter so a missing
      `AZURE_OPENAI_*` env var is visible immediately.
    * Offers a card-grid navigation to every primary route in the app.
    * Sprinkles live counts (cards / tools / memories / runs / …) into
      each tile so an operator can see at a glance what's populated.

  Refreshes on a 5 s timer; counts come straight from the contexts, no DB
  schema changes.
  """

  use AgenticAiAgentWeb, :live_view

  alias AgenticAiAgent.{Design, Eval, Failures, MCP, Memory, Skills, Traces}
  alias AgenticAiAgent.Agent.Runtime
  alias AgenticAiAgent.LLM.Pricing
  alias AgenticAiAgent.Tools.Registry, as: ToolRegistry

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(5_000, self(), :refresh)
      Phoenix.PubSub.subscribe(AgenticAiAgent.PubSub, Runtime.runs_topic())
    end

    {:ok, load(socket)}
  end

  @impl true
  def handle_info(:refresh, socket), do: {:noreply, load(socket)}
  def handle_info({:runs, _, _}, socket), do: {:noreply, load(socket)}
  def handle_info(_other, socket), do: {:noreply, socket}

  defp load(socket) do
    recent = safe(fn -> Traces.list_recent_runs(5) end, [])
    cost_today = safe(fn -> total_cost_today() end, 0)
    failures_24h = safe(fn -> recent_failure_count() end, 0)

    socket
    |> assign(:stats, gather_stats())
    |> assign(:llm, llm_status())
    |> assign(:recent_runs, recent)
    |> assign(:cost_today, cost_today)
    |> assign(:failures_24h, failures_24h)
  end

  defp gather_stats do
    safe_map(%{
      cards: fn -> length(Design.list_cards()) end,
      tools: fn -> length(ToolRegistry.list()) end,
      skills: fn -> length(Skills.list()) end,
      memories: fn -> Memory.count() end,
      runs: fn -> length(Traces.list_recent_runs(500)) end,
      evals: fn -> length(Eval.list_eval_runs(500)) end,
      mcp_servers: fn -> length(MCP.list_servers()) end,
      failures: fn -> Failures.total_count() end
    })
  end

  # Sum of cost_micro_usd across runs whose started_at is today (UTC).
  defp total_cost_today do
    import Ecto.Query

    today_start =
      DateTime.utc_now()
      |> DateTime.to_date()
      |> DateTime.new!(~T[00:00:00.000000])

    AgenticAiAgent.Repo.one(
      from r in AgenticAiAgent.Traces.Run,
        where: r.inserted_at >= ^DateTime.truncate(today_start, :second),
        select: coalesce(sum(r.cost_micro_usd), 0)
    )
  end

  defp recent_failure_count do
    import Ecto.Query

    since = DateTime.utc_now() |> DateTime.add(-86_400, :second) |> DateTime.truncate(:second)

    AgenticAiAgent.Repo.one(
      from o in AgenticAiAgent.Failures.FailureOccurrence,
        where: o.inserted_at >= ^since,
        select: count(o.id)
    )
  end

  defp safe(fun, default) do
    try do
      fun.()
    rescue
      _ -> default
    catch
      _, _ -> default
    end
  end

  defp safe_map(map) do
    Map.new(map, fn {k, f} ->
      value =
        try do
          f.()
        rescue
          _ -> 0
        catch
          _, _ -> 0
        end

      {k, value}
    end)
  end

  defp llm_status do
    cfg = Application.get_env(:agentic_ai_agent, AgenticAiAgent.LLM.AzureOpenAI, [])

    missing =
      [:endpoint, :api_key, :deployment]
      |> Enum.filter(fn k -> Keyword.get(cfg, k) in [nil, ""] end)

    emb_cfg = Application.get_env(:agentic_ai_agent, AgenticAiAgent.LLM.AzureOpenAIEmbeddings, [])

    embeddings_missing =
      [:endpoint, :api_key, :deployment]
      |> Enum.filter(fn k -> Keyword.get(emb_cfg, k) in [nil, ""] end)

    %{
      ok?: missing == [],
      missing: missing,
      deployment: Keyword.get(cfg, :deployment),
      api_version: Keyword.get(cfg, :api_version),
      endpoint: Keyword.get(cfg, :endpoint),
      embeddings_ok?: embeddings_missing == [],
      embeddings_deployment: Keyword.get(emb_cfg, :deployment),
      embeddings_api_version: Keyword.get(emb_cfg, :api_version)
    }
  end

  # ----- Route descriptors -----

  defp tiles(stats) do
    [
      %{
        path: "/chat",
        title: gettext("Chat"),
        subtitle: gettext("Talk to the agent. ReAct loop, tools, HITL approvals."),
        stat: stats.tools,
        stat_label: gettext("tools registered"),
        icon: "hero-chat-bubble-left-right",
        accent: "from-blue-500 to-indigo-600",
        primary?: true
      },
      %{
        path: "/runs",
        title: gettext("Runs"),
        subtitle: gettext("Every chat turn is a run. Inspect step-by-step traces."),
        stat: stats.runs,
        stat_label: gettext("runs recorded"),
        icon: "hero-clock",
        accent: "from-slate-500 to-slate-700"
      },
      %{
        path: "/memories",
        title: gettext("Memories"),
        subtitle: gettext("Long-term store with embedding-based semantic search."),
        stat: stats.memories,
        stat_label: gettext("memories"),
        icon: "hero-archive-box",
        accent: "from-amber-500 to-orange-600"
      },
      %{
        path: "/cards",
        title: gettext("Cards"),
        subtitle: gettext("The agent's behavioural contract — role, policies, workflows."),
        stat: stats.cards,
        stat_label: gettext("agentic cards"),
        icon: "hero-identification",
        accent: "from-violet-500 to-purple-700"
      },
      %{
        path: "/skills",
        title: gettext("Skills"),
        subtitle: gettext("Reusable procedures loaded into sub-agents on demand."),
        stat: stats.skills,
        stat_label: gettext("skills loaded"),
        icon: "hero-puzzle-piece",
        accent: "from-emerald-500 to-teal-700"
      },
      %{
        path: "/mcp",
        title: gettext("MCP"),
        subtitle: gettext("External Model Context Protocol servers and their tools."),
        stat: stats.mcp_servers,
        stat_label: gettext("servers connected"),
        icon: "hero-server-stack",
        accent: "from-cyan-500 to-sky-700"
      },
      %{
        path: "/evals",
        title: gettext("Evals"),
        subtitle: gettext("Golden dataset runs scored against the rubric."),
        stat: stats.evals,
        stat_label: gettext("eval runs"),
        icon: "hero-check-badge",
        accent: "from-rose-500 to-pink-700"
      },
      %{
        path: "/failures",
        title: gettext("Failures"),
        subtitle:
          gettext("Catalog of known failure modes and the runtime occurrences that match them."),
        stat: stats.failures,
        stat_label: gettext("occurrences"),
        icon: "hero-exclamation-triangle",
        accent: "from-red-500 to-rose-700"
      },
      %{
        path: "/tools",
        title: gettext("Tools"),
        subtitle:
          gettext(
            "Tool Contract catalog — preconditions, side effects, failure modes, retry policy."
          ),
        stat: stats.tools,
        stat_label: gettext("tools"),
        icon: "hero-wrench-screwdriver",
        accent: "from-zinc-500 to-stone-700"
      }
    ]
  end

  # Group the flat tile list into the navigation sections the UI displays.
  # Order matters — Talk first (most-used), Evaluation last (least-frequent).
  defp tile_groups(tiles) do
    by_path = Map.new(tiles, &{&1.path, &1})

    [
      {gettext("Talk"), [by_path["/chat"]]},
      {gettext("Observability"), [by_path["/runs"], by_path["/failures"]]},
      {gettext("Behavior"), [by_path["/cards"], by_path["/skills"], by_path["/memories"]]},
      {gettext("Integration"), [by_path["/tools"], by_path["/mcp"]]},
      {gettext("Evaluation"), [by_path["/evals"]]}
    ]
    |> Enum.map(fn {name, list} -> {name, Enum.reject(list, &is_nil/1)} end)
  end

  # ----- Render -----

  @impl true
  def render(assigns) do
    tiles = tiles(assigns.stats)

    assigns =
      assigns
      |> assign(:tiles, tiles)
      |> assign(:tile_groups, tile_groups(tiles))

    ~H"""
    <Layouts.app flash={@flash} current_path={@current_path} locale={@locale}>
      <div class="space-y-8">
        <.hero llm={@llm} />

        <.llm_banner :if={!@llm.ok?} llm={@llm} />

        <.summary_strip
          cost_today={@cost_today}
          failures_24h={@failures_24h}
          runs_total={@stats.runs}
        />

        <.recent_runs :if={@recent_runs != []} runs={@recent_runs} />

        <section
          :for={{group_name, group_tiles} <- @tile_groups}
          :if={group_tiles != []}
          class="space-y-3"
        >
          <h2 class="eyebrow">
            {group_name}
          </h2>
          <div class={[
            "grid grid-cols-1 gap-4",
            grid_cols(length(group_tiles))
          ]}>
            <.tile :for={tile <- group_tiles} tile={tile} />
          </div>
        </section>

        <section class="space-y-3">
          <h2 class="eyebrow">
            {gettext("Quick reference")}
          </h2>
          <div class="grid grid-cols-1 gap-3 text-sm md:grid-cols-2">
            <.quick_card
              title={gettext("CLI")}
              lines={[
                gettext("./run.sh — start with Azure OpenAI env"),
                gettext("mix agent.eval — run the golden dataset"),
                gettext("mix run priv/repo/seeds.exs — reload cards from YAML")
              ]}
            />
            <.quick_card
              title={gettext("Authoring")}
              lines={[
                gettext("priv/cards/<slug>.yaml — agentic card"),
                gettext("priv/skills/<slug>/SKILL.md — skill"),
                gettext("priv/eval/golden/*.jsonl — golden cases")
              ]}
            />
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end

  # ----- Components -----

  attr :cost_today, :integer, required: true
  attr :failures_24h, :integer, required: true
  attr :runs_total, :integer, required: true

  defp summary_strip(assigns) do
    ~H"""
    <section class="grid grid-cols-1 gap-3 sm:grid-cols-3">
      <.stat_card
        label={gettext("Today's LLM cost")}
        icon="hero-banknotes"
        accent="bg-emerald-100 dark:bg-emerald-900/40 text-emerald-800 dark:text-emerald-200"
      >
        <span class="font-mono text-xl">{Pricing.format(@cost_today || 0)}</span>
      </.stat_card>
      <.stat_card
        label={gettext("Failures in last 24h")}
        icon="hero-exclamation-triangle"
        accent={fail_accent(@failures_24h)}
      >
        <.link navigate={~p"/failures"} class="font-mono text-xl hover:underline">
          {@failures_24h || 0}
        </.link>
      </.stat_card>
      <.stat_card
        label={gettext("Total runs")}
        icon="hero-clock"
        accent="bg-slate-100 dark:bg-slate-800 text-slate-800 dark:text-slate-200"
      >
        <.link navigate={~p"/runs"} class="font-mono text-xl hover:underline">{@runs_total}</.link>
      </.stat_card>
    </section>
    """
  end

  attr :label, :string, required: true
  attr :icon, :string, required: true
  attr :accent, :string, required: true
  slot :inner_block, required: true

  defp stat_card(assigns) do
    ~H"""
    <div class="flex items-center gap-4 rounded-full border border-base-content/10 bg-base-200 px-5 py-4">
      <div class={["flex h-11 w-11 items-center justify-center rounded-full", @accent]}>
        <.icon name={@icon} class="h-5 w-5" />
      </div>
      <div class="flex flex-col">
        <span class="text-xs font-bold uppercase tracking-[0.04em] opacity-60">{@label}</span>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  defp fail_accent(0), do: "bg-base-200 opacity-70"

  defp fail_accent(n) when is_integer(n) and n > 0,
    do: "bg-red-100 dark:bg-red-900/40 text-red-800 dark:text-red-200"

  defp fail_accent(_), do: "bg-base-200 opacity-70"

  attr :runs, :list, required: true

  defp recent_runs(assigns) do
    ~H"""
    <section class="space-y-3">
      <header class="flex items-baseline justify-between">
        <h2 class="eyebrow">
          {gettext("Recent activity")}
        </h2>
        <.link
          navigate={~p"/runs"}
          class="rounded-full border border-base-content/20 px-3 py-1 text-xs opacity-80 hover:bg-base-200"
        >
          {gettext("all runs")} →
        </.link>
      </header>

      <ul class="divide-y divide-base-content/10 overflow-hidden rounded-[40px] border border-base-content/10 bg-base-200">
        <li :for={r <- @runs} class="flex items-center gap-3 p-3 text-sm">
          <span class={[
            "rounded-full px-2 py-0.5 text-[10px] font-mono uppercase",
            run_status_color(r.status)
          ]}>
            {r.status}
          </span>
          <.link navigate={~p"/runs/#{r.id}"} class="flex-1 truncate hover:underline">
            {truncate(r.user_input, 90)}
          </.link>
          <span :if={r.cost_micro_usd && r.cost_micro_usd > 0} class="font-mono text-xs opacity-70">
            {Pricing.format(r.cost_micro_usd)}
          </span>
          <span class="font-mono text-xs opacity-50">
            {format_latency(r.latency_ms)}
          </span>
        </li>
      </ul>
    </section>
    """
  end

  defp run_status_color("done"),
    do: "bg-green-100 dark:bg-green-900/40 text-green-800 dark:text-green-200"

  defp run_status_color("failed"),
    do: "bg-red-100 dark:bg-red-900/40 text-red-800 dark:text-red-200"

  defp run_status_color("running"),
    do: "bg-yellow-100 dark:bg-yellow-900/40 text-yellow-800 dark:text-yellow-200"

  defp run_status_color("awaiting_approval"),
    do: "bg-orange-100 dark:bg-orange-900/40 text-orange-800 dark:text-orange-200"

  defp run_status_color("cancelled"), do: "bg-base-300 text-base-content"
  defp run_status_color(_), do: "bg-base-200"

  defp truncate(nil, _), do: ""

  defp truncate(text, n) when is_binary(text) do
    if String.length(text) > n, do: String.slice(text, 0, n) <> "…", else: text
  end

  defp format_latency(nil), do: "—"
  defp format_latency(ms) when is_integer(ms) and ms < 1000, do: "#{ms} ms"
  defp format_latency(ms) when is_integer(ms), do: "#{Float.round(ms / 1000, 2)} s"
  defp format_latency(_), do: "—"

  defp grid_cols(1), do: "sm:grid-cols-1 lg:grid-cols-1"
  defp grid_cols(2), do: "sm:grid-cols-2 lg:grid-cols-2"
  defp grid_cols(_), do: "sm:grid-cols-2 lg:grid-cols-3"

  attr :llm, :map, required: true

  defp hero(assigns) do
    ~H"""
    <header class="relative overflow-hidden rounded-2xl border border-base-content/10 bg-base-200 p-8 shadow-[rgba(0,0,0,0.08)_0px_24px_48px_0px]">
      <div
        class="pointer-events-none absolute -right-10 -top-8 hidden text-[96px] font-medium leading-none tracking-[-0.02em] text-base-300 md:block"
        aria-hidden="true"
      >
        Agentic
      </div>
      <div class="relative flex flex-wrap items-start justify-between gap-6">
        <div class="space-y-2">
          <p class="eyebrow">{gettext("Agent workspace")}</p>
          <h1 class="max-w-3xl text-[40px] font-medium leading-[1] tracking-[-0.02em] md:text-[64px]">
            {gettext("Agentic AI Agent")}
          </h1>
          <p class="max-w-2xl text-base leading-[1.4] opacity-70">
            {gettext(
              "An Elixir/Phoenix implementation of the agent architecture documented in docs/: core LLM, short- and long-term memory, tool registry, ReAct loop with HITL, sub-agents, MCP, sandbox, and a rubric-based eval harness."
            )}
          </p>
        </div>

        <.llm_chip llm={@llm} />
      </div>

      <div class="relative mt-8 flex flex-wrap gap-2">
        <.link
          navigate={~p"/chat"}
          class="inline-flex items-center gap-2 px-6 py-2 text-base font-medium"
          style="background:#141413;color:#F3F0EE;border-radius:20px;letter-spacing:-0.02em;"
        >
          <.icon name="hero-chat-bubble-left-right-solid" class="h-4 w-4" />
          {gettext("Start a chat")}
        </.link>
        <.link
          navigate={~p"/runs"}
          class="inline-flex items-center gap-2 rounded-full border border-base-content px-6 py-2 text-base font-medium tracking-[-0.02em] hover:bg-base-100"
        >
          <.icon name="hero-clock" class="h-4 w-4" />
          {gettext("View runs")}
        </.link>
      </div>
    </header>
    """
  end

  attr :llm, :map, required: true

  defp llm_chip(%{llm: %{ok?: true}} = assigns) do
    ~H"""
    <div class="rounded-[40px] border border-emerald-300 dark:border-emerald-700 bg-base-100 px-4 py-3 text-xs">
      <div class="flex items-center gap-2 font-semibold text-emerald-800 dark:text-emerald-200">
        <span class="inline-block h-2 w-2 rounded-full bg-emerald-500"></span>
        {gettext("LLM configured")}
      </div>
      <dl class="mt-1 grid grid-cols-[auto_1fr] gap-x-2 font-mono text-[10px] text-emerald-900/80 dark:text-emerald-200/80">
        <dt>{gettext("deploy")}</dt>
        <dd>{@llm.deployment}</dd>
        <dt>{gettext("api")}</dt>
        <dd>{@llm.api_version}</dd>
        <dt :if={@llm.embeddings_ok?}>{gettext("embed")}</dt>
        <dd :if={@llm.embeddings_ok?}>{@llm.embeddings_deployment}</dd>
        <dt :if={@llm.embeddings_ok?}>{gettext("embed api")}</dt>
        <dd :if={@llm.embeddings_ok?}>{@llm.embeddings_api_version}</dd>
      </dl>
    </div>
    """
  end

  defp llm_chip(assigns) do
    ~H"""
    <div class="rounded-[40px] border border-red-300 dark:border-red-700 bg-base-100 px-4 py-3 text-xs">
      <div class="flex items-center gap-2 font-semibold text-red-800 dark:text-red-200">
        <span class="inline-block h-2 w-2 rounded-full bg-red-500"></span>
        {gettext("LLM not configured")}
      </div>
      <p class="mt-1 text-[10px] text-red-900/80 dark:text-red-200/80">
        {gettext("missing:")} {Enum.map_join(@llm.missing, ", ", &Atom.to_string/1)}
      </p>
    </div>
    """
  end

  attr :llm, :map, required: true

  defp llm_banner(assigns) do
    ~H"""
    <div class="rounded-[40px] border border-red-300 dark:border-red-700 bg-red-50 dark:bg-red-950/40 p-5">
      <div class="flex items-start gap-3">
        <.icon name="hero-exclamation-triangle" class="h-5 w-5 flex-none text-red-600" />
        <div class="space-y-2 text-sm text-red-900 dark:text-red-200">
          <p class="font-semibold">
            {gettext("Azure OpenAI is not fully configured.")}
          </p>
          <p>
            {gettext("Missing env:")} <code>{Enum.map_join(@llm.missing, ", ", &("AZURE_OPENAI_" <> String.upcase(Atom.to_string(&1))))}</code>. {gettext(
              "The chat surface will return"
            ) <> " "}<code>{"{:missing_config, …}"}</code> {gettext("until set.")}
          </p>
          <p class="font-mono text-xs">
            {gettext("Quick fix:")} <code>./run.sh</code> {gettext("(see also config/runtime.exs).")}
          </p>
        </div>
      </div>
    </div>
    """
  end

  attr :tile, :map, required: true

  defp tile(assigns) do
    ~H"""
    <.link
      navigate={@tile.path}
      class={[
        "group relative flex min-h-64 flex-col gap-4 overflow-hidden rounded-[40px] border border-base-content/10 bg-base-200 p-6 transition hover:-translate-y-0.5 hover:shadow-[rgba(0,0,0,0.08)_0px_24px_48px_0px]",
        @tile[:primary?] && "ring-2 ring-base-content/10"
      ]}
    >
      <div class="absolute -right-24 -top-24 h-56 w-56 rounded-full border border-[#F37338]/50" />

      <div class="flex items-start justify-between">
        <div class="inline-flex h-14 w-14 items-center justify-center rounded-full border border-base-content/10 bg-base-100 text-base-content">
          <.icon name={@tile.icon} class="h-5 w-5" />
        </div>
        <code class="rounded-full bg-base-100 px-3 py-1 font-mono text-[10px] opacity-70">
          {@tile.path}
        </code>
      </div>

      <div class="space-y-1">
        <h3 class="text-2xl font-medium leading-[1.2] tracking-[-0.02em]">{@tile.title}</h3>
        <p class="text-sm opacity-70">{@tile.subtitle}</p>
      </div>

      <div class="mt-auto flex items-baseline justify-between">
        <div>
          <span class="text-2xl font-bold tabular-nums">{@tile.stat}</span>
          <span class="ml-1 text-xs opacity-60">{@tile.stat_label}</span>
        </div>
        <span class="flex h-12 w-12 items-center justify-center rounded-full bg-white text-xl text-[#141413] transition group-hover:translate-x-0.5">
          →
        </span>
      </div>
    </.link>
    """
  end

  attr :title, :string, required: true
  attr :lines, :list, required: true

  defp quick_card(assigns) do
    ~H"""
    <div class="rounded-[40px] border border-base-content/10 bg-base-200 p-5">
      <h3 class="eyebrow mb-3">{@title}</h3>
      <ul class="space-y-1 font-mono text-xs">
        <li :for={line <- @lines} class="opacity-80">{line}</li>
      </ul>
    </div>
    """
  end
end
