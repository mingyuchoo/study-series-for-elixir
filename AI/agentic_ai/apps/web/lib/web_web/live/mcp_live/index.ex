defmodule WebWeb.McpLive.Index do
  use WebWeb, :live_view

  alias Core.Contexts.Mcps

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign_mcps(socket)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    mcp = Mcps.get_mcp!(id)
    {:ok, _} = Mcps.delete_mcp(mcp)

    {:noreply,
     socket
     |> assign_mcps()
     |> put_flash(:info, "MCP가 삭제되었습니다.")}
  end

  @impl true
  def handle_event("toggle", %{"id" => id}, socket) do
    mcp = Mcps.get_mcp!(id)
    {:ok, _} = Mcps.update_mcp(mcp, %{enabled: !mcp.enabled})
    {:noreply, assign_mcps(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-full bg-base-100">
      <section class="border-b border-base-300 bg-base-100">
        <div class="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
          <div class="flex flex-col gap-6 lg:flex-row lg:items-end lg:justify-between">
            <div class="max-w-3xl">
              <p class="text-sm text-base-content/60">Admin / MCP</p>
              <h1 class="mt-3 text-4xl font-light leading-tight text-base-content">
                MCP 서버 관리
              </h1>
              <p class="mt-3 text-sm leading-6 text-base-content/70">
                Model Context Protocol 서버의 실행 명령, 환경 변수, 활성 상태를 관리합니다.
              </p>
            </div>
            <.link navigate={~p"/admin/mcps/new"} class="btn btn-primary gap-2 whitespace-nowrap">
              <.icon name="hero-plus" class="size-4" /> 새 MCP
            </.link>
          </div>
        </div>
      </section>

      <section class="mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8">
        <div class="grid gap-px border border-base-300 bg-base-300 sm:grid-cols-2 lg:grid-cols-4">
          <.summary_tile label="전체 MCP" value={@summary.total} />
          <.summary_tile label="활성" value={@summary.enabled} />
          <.summary_tile label="사용 가능" value={@summary.ready} />
          <.summary_tile label="환경변수 누락" value={@summary.unavailable} />
        </div>

        <div class="mt-6 hidden border border-base-300 bg-base-100 md:block">
          <table class="table table-fixed w-full">
            <thead>
              <tr>
                <th class="w-[16%] text-xs font-semibold uppercase text-base-content/60">이름</th>
                <th class="w-[34%] text-xs font-semibold uppercase text-base-content/60">명령</th>
                <th class="w-[18%] text-xs font-semibold uppercase text-base-content/60">환경 변수</th>
                <th class="w-[13%] text-xs font-semibold uppercase text-base-content/60">상태</th>
                <th class="w-[9%] text-xs font-semibold uppercase text-base-content/60">활성화</th>
                <th class="w-[10%] text-xs font-semibold uppercase text-base-content/60">작업</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={mcp <- @mcps} class="border-t border-base-300">
                <td class="font-semibold break-words align-top text-sm">{mcp.name}</td>
                <td class="text-xs font-mono break-all whitespace-normal align-top text-base-content/70">
                  {mcp.command} {Enum.join(mcp.args, " ")}
                </td>
                <td class="text-xs align-top">
                  <span
                    :for={{k, _v} <- mcp.env || %{}}
                    class="badge badge-ghost badge-sm mr-1 mb-1 max-w-full break-all whitespace-normal h-auto min-h-5"
                  >
                    {k}
                  </span>
                </td>
                <td class="align-top">
                  <span class={[
                    "badge badge-sm gap-1 h-auto min-h-5 whitespace-normal text-xs font-normal",
                    status_badge(mcp.status)
                  ]}>
                    <span class={["status", status_dot(mcp.status)]} />
                    {status_label(mcp.status)}
                  </span>
                </td>
                <td class="align-top">
                  <input
                    type="checkbox"
                    class="toggle toggle-sm"
                    checked={mcp.enabled}
                    phx-click="toggle"
                    phx-value-id={mcp.id}
                    aria-label="MCP 활성화"
                  />
                </td>
                <td class="align-top">
                  <div class="join join-vertical xl:join-horizontal">
                    <.link
                      navigate={~p"/admin/mcps/#{mcp.id}/edit"}
                      class="btn btn-ghost btn-xs join-item"
                    >
                      편집
                    </.link>
                    <button
                      phx-click="delete"
                      phx-value-id={mcp.id}
                      data-confirm="삭제하시겠습니까?"
                      class="btn btn-ghost btn-xs text-error join-item"
                    >
                      삭제
                    </button>
                  </div>
                </td>
              </tr>
              <tr :if={@mcps == []}>
                <td colspan="6" class="text-center text-base-content/50 py-10">
                  등록된 MCP가 없습니다.
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div class="mt-6 space-y-3 md:hidden">
          <div :for={mcp <- @mcps} class="border border-base-300 bg-base-100 p-4">
            <div class="flex items-start justify-between gap-3">
              <div class="min-w-0">
                <div class="break-words text-sm font-semibold">{mcp.name}</div>
                <div class="mt-1 break-all font-mono text-xs text-base-content/70">
                  {mcp.command} {Enum.join(mcp.args, " ")}
                </div>
              </div>
              <input
                type="checkbox"
                class="toggle toggle-sm shrink-0"
                checked={mcp.enabled}
                phx-click="toggle"
                phx-value-id={mcp.id}
                aria-label="MCP 활성화"
              />
            </div>

            <div class="mt-3 flex flex-wrap items-center gap-1 text-xs">
              <span class={[
                "badge badge-sm gap-1 h-auto min-h-5 whitespace-normal text-xs font-normal",
                status_badge(mcp.status)
              ]}>
                <span class={["status", status_dot(mcp.status)]} />
                {status_label(mcp.status)}
              </span>
              <span
                :for={{k, _v} <- mcp.env || %{}}
                class="badge badge-ghost badge-sm max-w-full break-all whitespace-normal h-auto min-h-5"
              >
                {k}
              </span>
            </div>

            <div class="mt-3 flex">
              <div class="join">
                <.link
                  navigate={~p"/admin/mcps/#{mcp.id}/edit"}
                  class="btn btn-ghost btn-xs join-item"
                >
                  편집
                </.link>
                <button
                  phx-click="delete"
                  phx-value-id={mcp.id}
                  data-confirm="삭제하시겠습니까?"
                  class="btn btn-ghost btn-xs text-error join-item"
                >
                  삭제
                </button>
              </div>
            </div>
          </div>

          <div
            :if={@mcps == []}
            class="border border-base-300 bg-base-100 py-10 text-center text-base-content/50"
          >
            등록된 MCP가 없습니다.
          </div>
        </div>
      </section>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true

  defp summary_tile(assigns) do
    ~H"""
    <div class="bg-base-100 p-4">
      <div class="text-xs text-base-content/60">{@label}</div>
      <div class="mt-4 text-4xl font-light leading-none">{@value}</div>
    </div>
    """
  end

  defp assign_mcps(socket) do
    mcps = Mcps.list_mcps_with_status()

    socket
    |> assign(:mcps, mcps)
    |> assign(:summary, %{
      total: length(mcps),
      enabled: Enum.count(mcps, & &1.enabled),
      ready: Enum.count(mcps, &(&1.status == :ready)),
      unavailable: Enum.count(mcps, &(&1.status == :unavailable))
    })
  end

  defp status_badge(:ready), do: "badge-success"
  defp status_badge(:unavailable), do: "badge-error"
  defp status_badge(:disabled), do: "badge-ghost"
  defp status_badge(_), do: "badge-ghost"

  defp status_dot(:ready), do: "status-success"
  defp status_dot(:unavailable), do: "status-error"
  defp status_dot(:disabled), do: "status-neutral"
  defp status_dot(_), do: "status-neutral"

  defp status_label(:ready), do: "사용 가능"
  defp status_label(:unavailable), do: "환경변수 누락"
  defp status_label(:disabled), do: "비활성"
  defp status_label(_), do: "확인불가"
end
