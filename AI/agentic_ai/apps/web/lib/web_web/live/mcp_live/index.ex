defmodule WebWeb.McpLive.Index do
  use WebWeb, :live_view

  alias Core.Contexts.Mcps

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :mcps, Mcps.list_mcps_with_status())}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    mcp = Mcps.get_mcp!(id)
    {:ok, _} = Mcps.delete_mcp(mcp)

    {:noreply,
     socket
     |> assign(:mcps, Mcps.list_mcps_with_status())
     |> put_flash(:info, "MCP가 삭제되었습니다.")}
  end

  @impl true
  def handle_event("toggle", %{"id" => id}, socket) do
    mcp = Mcps.get_mcp!(id)
    {:ok, _} = Mcps.update_mcp(mcp, %{enabled: !mcp.enabled})
    {:noreply, assign(socket, :mcps, Mcps.list_mcps_with_status())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-6xl bg-base-100 p-6">
      <.header>
        MCP 서버 관리
        <:subtitle>Model Context Protocol 서버 설정을 관리합니다.</:subtitle>
        <:actions>
          <.link navigate={~p"/admin/mcps/new"} class="btn btn-primary gap-2">
            <.icon name="hero-plus" class="size-4" /> 새 MCP
          </.link>
        </:actions>
      </.header>

      <div class="overflow-x-auto border border-base-300 bg-base-100">
        <table class="table table-zebra">
          <thead>
            <tr>
              <th>이름</th>
              <th>명령</th>
              <th>환경 변수</th>
              <th>상태</th>
              <th>활성화</th>
              <th class="w-40">작업</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={mcp <- @mcps}>
              <td class="font-semibold">{mcp.name}</td>
              <td class="text-xs font-mono">
                {mcp.command} {Enum.join(mcp.args, " ")}
              </td>
              <td class="text-xs">
                <span :for={{k, _v} <- mcp.env || %{}} class="badge badge-ghost badge-sm mr-1">
                  {k}
                </span>
              </td>
              <td>
                <span class={["badge gap-1", status_badge(mcp.status)]}>
                  <span class={["status", status_dot(mcp.status)]} />
                  {status_label(mcp.status)}
                </span>
              </td>
              <td>
                <input
                  type="checkbox"
                  class="toggle toggle-sm"
                  checked={mcp.enabled}
                  phx-click="toggle"
                  phx-value-id={mcp.id}
                  aria-label="MCP 활성화"
                />
              </td>
              <td>
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
              </td>
            </tr>
            <tr :if={@mcps == []}>
              <td colspan="6" class="text-center opacity-50 py-8">
                등록된 MCP가 없습니다.
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp status_badge(:ready), do: "badge-success"
  defp status_badge(:unavailable), do: "badge-error"
  defp status_badge(_), do: "badge-ghost"

  defp status_dot(:ready), do: "status-success"
  defp status_dot(:unavailable), do: "status-error"
  defp status_dot(_), do: "status-neutral"

  defp status_label(:ready), do: "사용 가능"
  defp status_label(:unavailable), do: "환경변수 누락"
  defp status_label(_), do: "확인불가"
end
