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
    <div class="max-w-6xl mx-auto p-6">
      <div class="flex items-center justify-between mb-6">
        <div>
          <h1 class="text-3xl font-bold">MCP 서버 관리</h1>
          <p class="text-base-content/60">Model Context Protocol 서버 설정을 관리합니다.</p>
        </div>
        <.link navigate={~p"/admin/mcps/new"} class="btn btn-primary gap-2">
          <.icon name="hero-plus" class="w-4 h-4" /> 새 MCP
        </.link>
      </div>

      <div class="overflow-x-auto bg-base-100 rounded-lg shadow">
        <table class="table">
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
            <%= for mcp <- @mcps do %>
              <tr>
                <td class="font-semibold">{mcp.name}</td>
                <td class="text-xs font-mono">
                  {mcp.command} {Enum.join(mcp.args, " ")}
                </td>
                <td class="text-xs">
                  <%= for {k, _v} <- (mcp.env || %{}) do %>
                    <span class="badge badge-ghost badge-sm">{k}</span>
                  <% end %>
                </td>
                <td>
                  <span class={status_badge(mcp.status)}>{status_label(mcp.status)}</span>
                </td>
                <td>
                  <button phx-click="toggle" phx-value-id={mcp.id} class="btn btn-ghost btn-xs">
                    <input type="checkbox" class="toggle toggle-sm" checked={mcp.enabled} />
                  </button>
                </td>
                <td>
                  <div class="flex gap-1">
                    <.link navigate={~p"/admin/mcps/#{mcp.id}/edit"} class="btn btn-ghost btn-xs">
                      편집
                    </.link>
                    <button
                      phx-click="delete"
                      phx-value-id={mcp.id}
                      data-confirm="삭제하시겠습니까?"
                      class="btn btn-ghost btn-xs text-error"
                    >
                      삭제
                    </button>
                  </div>
                </td>
              </tr>
            <% end %>
            <%= if @mcps == [] do %>
              <tr>
                <td colspan="6" class="text-center opacity-50 py-8">
                  등록된 MCP가 없습니다.
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp status_badge(:ready), do: "badge badge-success gap-1"
  defp status_badge(:unavailable), do: "badge badge-error gap-1"
  defp status_badge(_), do: "badge badge-ghost gap-1"

  defp status_label(:ready), do: "사용 가능"
  defp status_label(:unavailable), do: "환경변수 누락"
  defp status_label(_), do: "확인불가"
end
