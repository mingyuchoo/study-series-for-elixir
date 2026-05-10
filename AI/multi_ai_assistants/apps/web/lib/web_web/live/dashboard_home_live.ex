defmodule WebWeb.DashboardHomeLive do
  use WebWeb, :live_view

  import Ecto.Query

  alias Core.Contexts.{Agents, Mcps}
  alias Core.Repo
  alias Core.Schema.{AgentTask, Conversation, Message}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign_dashboard(socket)}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, assign_dashboard(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-full bg-base-100">
      <section class="border-b border-base-300 bg-base-100">
        <div class="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
          <div class="flex flex-col gap-6 lg:flex-row lg:items-end lg:justify-between">
            <div class="max-w-3xl">
              <p class="text-sm text-base-content/60">Admin / Dashboard</p>
              <h1 class="mt-3 text-4xl font-light leading-tight text-base-content">
                운영 대시보드
              </h1>
              <p class="mt-3 text-sm leading-6 text-base-content/70">
                Agentic AI 런타임, 에이전트, MCP 서버, 대화 흐름을 한 화면에서 점검합니다.
              </p>
            </div>
            <div class="flex flex-wrap gap-2">
              <button phx-click="refresh" class="btn btn-primary gap-2">
                <.icon name="hero-arrow-path" class="size-4" /> 새로고침
              </button>
              <.link navigate={~p"/admin/dashboard/metrics"} class="btn btn-ghost gap-2">
                <.icon name="hero-chart-bar" class="size-4" /> 상세 메트릭
              </.link>
            </div>
          </div>
        </div>
      </section>

      <section class="mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8">
        <div class="grid gap-px border border-base-300 bg-base-300 sm:grid-cols-2 xl:grid-cols-4">
          <.metric_tile
            label="활성 에이전트"
            value={@summary.active_agents}
            detail={"전체 #{@summary.total_agents}개"}
          />
          <.metric_tile
            label="MCP 사용 가능"
            value={@summary.ready_mcps}
            detail={"전체 #{@summary.total_mcps}개"}
          />
          <.metric_tile
            label="활성 대화"
            value={@summary.active_conversations}
            detail={"메시지 #{@summary.total_messages}개"}
          />
          <.metric_tile
            label="진행 중 작업"
            value={@summary.running_tasks}
            detail={"실패 #{@summary.failed_tasks}개"}
          />
        </div>

        <div class="mt-6 grid gap-6 xl:grid-cols-[1.3fr_0.7fr]">
          <section class="border border-base-300 bg-base-100">
            <div class="border-b border-base-300 px-4 py-3">
              <h2 class="text-xl font-normal">시스템 상태</h2>
            </div>
            <div class="grid gap-px bg-base-300 md:grid-cols-2">
              <.system_cell label="노드" value={@runtime.node} />
              <.system_cell
                label="OTP / Elixir"
                value={"OTP #{@runtime.otp} · Elixir #{@runtime.elixir}"}
              />
              <.system_cell label="스케줄러" value={"#{@runtime.schedulers} online"} />
              <.system_cell
                label="프로세스"
                value={"#{@runtime.process_count} / #{@runtime.process_limit}"}
              />
              <.system_cell label="메모리" value={@runtime.memory_total} />
              <.system_cell label="VM 가동 시간" value={@runtime.uptime} />
            </div>
          </section>

          <section class="border border-base-300 bg-base-100">
            <div class="border-b border-base-300 px-4 py-3">
              <h2 class="text-xl font-normal">빠른 이동</h2>
            </div>
            <nav class="divide-y divide-base-300">
              <.quick_link to={~p"/admin/agents"} icon="hero-cpu-chip" label="에이전트 관리" />
              <.quick_link to={~p"/admin/mcps"} icon="hero-server-stack" label="MCP 서버 관리" />
              <.quick_link
                to={~p"/admin/dashboard/metrics"}
                icon="hero-chart-bar"
                label="LiveDashboard 메트릭"
              />
              <.quick_link
                to={~p"/admin/dashboard/os_mon"}
                icon="hero-command-line"
                label="OS 모니터"
              />
            </nav>
          </section>
        </div>

        <div class="mt-6 grid gap-6 xl:grid-cols-2">
          <section class="border border-base-300 bg-base-100">
            <div class="flex items-center justify-between border-b border-base-300 px-4 py-3">
              <h2 class="text-xl font-normal">에이전트</h2>
              <.link navigate={~p"/admin/agents"} class="link link-primary text-sm">관리</.link>
            </div>
            <div class="divide-y divide-base-300">
              <div :for={agent <- @agents} class="grid grid-cols-[1fr_auto] gap-4 px-4 py-3">
                <div class="min-w-0">
                  <div class="truncate text-sm font-semibold">{agent.display_name || agent.name}</div>
                  <div class="mt-1 text-xs text-base-content/60">
                    {agent.type} · {agent.model || "-"}
                  </div>
                </div>
                <span class={["badge badge-sm", agent_status_badge(agent.status)]}>
                  {agent.status}
                </span>
              </div>
              <div :if={@agents == []} class="px-4 py-8 text-sm text-base-content/50">
                등록된 에이전트가 없습니다.
              </div>
            </div>
          </section>

          <section class="border border-base-300 bg-base-100">
            <div class="flex items-center justify-between border-b border-base-300 px-4 py-3">
              <h2 class="text-xl font-normal">MCP 서버</h2>
              <.link navigate={~p"/admin/mcps"} class="link link-primary text-sm">관리</.link>
            </div>
            <div class="divide-y divide-base-300">
              <div :for={mcp <- @mcps} class="grid grid-cols-[1fr_auto] gap-4 px-4 py-3">
                <div class="min-w-0">
                  <div class="truncate text-sm font-semibold">{mcp.name}</div>
                  <div class="mt-1 truncate font-mono text-xs text-base-content/60">
                    {mcp.command} {Enum.join(mcp.args, " ")}
                  </div>
                </div>
                <span class={["badge badge-sm", mcp_status_badge(mcp.status)]}>
                  {mcp_status_label(mcp.status)}
                </span>
              </div>
              <div :if={@mcps == []} class="px-4 py-8 text-sm text-base-content/50">
                등록된 MCP 서버가 없습니다.
              </div>
            </div>
          </section>
        </div>

        <section class="mt-6 border border-base-300 bg-base-100">
          <div class="border-b border-base-300 px-4 py-3">
            <h2 class="text-xl font-normal">최근 대화</h2>
          </div>
          <div class="divide-y divide-base-300">
            <div :for={conversation <- @recent_conversations} class="px-4 py-3">
              <div class="break-words text-sm font-semibold">{conversation.title}</div>
              <div class="mt-1 text-xs text-base-content/60">
                {conversation.status} · {format_datetime(conversation.updated_at)}
              </div>
            </div>
            <div :if={@recent_conversations == []} class="px-4 py-8 text-sm text-base-content/50">
              최근 대화가 없습니다.
            </div>
          </div>
        </section>
      </section>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :detail, :string, required: true

  defp metric_tile(assigns) do
    ~H"""
    <div class="bg-base-100 p-4">
      <div class="text-xs text-base-content/60">{@label}</div>
      <div class="mt-4 text-4xl font-light leading-none">{@value}</div>
      <div class="mt-2 text-xs text-base-content/60">{@detail}</div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp system_cell(assigns) do
    ~H"""
    <div class="bg-base-100 px-4 py-3">
      <div class="text-xs text-base-content/60">{@label}</div>
      <div class="mt-1 break-words text-sm">{@value}</div>
    </div>
    """
  end

  attr :to, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true

  defp quick_link(assigns) do
    ~H"""
    <.link
      navigate={@to}
      class="flex items-center justify-between px-4 py-3 text-sm hover:bg-base-200"
    >
      <span class="flex items-center gap-2">
        <.icon name={@icon} class="size-4" /> {@label}
      </span>
      <.icon name="hero-arrow-right" class="size-4 text-primary" />
    </.link>
    """
  end

  defp assign_dashboard(socket) do
    agents = Agents.list_agents()
    mcps = Mcps.list_mcps_with_status()

    socket
    |> assign(:summary, build_summary(agents, mcps))
    |> assign(:runtime, runtime_snapshot())
    |> assign(:agents, Enum.take(agents, 6))
    |> assign(:mcps, Enum.take(mcps, 6))
    |> assign(:recent_conversations, recent_conversations())
  end

  defp build_summary(agents, mcps) do
    %{
      total_agents: length(agents),
      active_agents: Enum.count(agents, &(&1.status == :active)),
      total_mcps: length(mcps),
      ready_mcps: Enum.count(mcps, &(&1.status == :ready)),
      active_conversations:
        Repo.aggregate(from(c in Conversation, where: c.status == :active), :count),
      total_messages: Repo.aggregate(Message, :count),
      running_tasks:
        Repo.aggregate(from(t in AgentTask, where: t.status == :in_progress), :count),
      failed_tasks: Repo.aggregate(from(t in AgentTask, where: t.status == :failed), :count)
    }
  end

  defp runtime_snapshot do
    memory = :erlang.memory()
    {uptime_ms, _} = :erlang.statistics(:wall_clock)

    %{
      node: Atom.to_string(node()),
      otp: System.otp_release(),
      elixir: System.version(),
      schedulers: System.schedulers_online(),
      process_count: :erlang.system_info(:process_count),
      process_limit: :erlang.system_info(:process_limit),
      memory_total: format_bytes(Keyword.fetch!(memory, :total)),
      uptime: format_duration(uptime_ms)
    }
  end

  defp recent_conversations do
    Conversation
    |> order_by([c], desc: c.updated_at)
    |> limit(5)
    |> Repo.all()
  end

  defp agent_status_badge(:active), do: "badge-success"
  defp agent_status_badge(:disabled), do: "badge-ghost"
  defp agent_status_badge(_), do: "badge-ghost"

  defp mcp_status_badge(:ready), do: "badge-success"
  defp mcp_status_badge(:unavailable), do: "badge-error"
  defp mcp_status_badge(:disabled), do: "badge-ghost"
  defp mcp_status_badge(_), do: "badge-ghost"

  defp mcp_status_label(:ready), do: "사용 가능"
  defp mcp_status_label(:unavailable), do: "환경변수 누락"
  defp mcp_status_label(:disabled), do: "비활성"
  defp mcp_status_label(_), do: "확인불가"

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  defp format_duration(ms) do
    seconds = div(ms, 1000)
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)

    cond do
      hours > 0 -> "#{hours}h #{minutes}m"
      minutes > 0 -> "#{minutes}m"
      true -> "#{seconds}s"
    end
  end

  defp format_datetime(nil), do: "-"
  defp format_datetime(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
end
