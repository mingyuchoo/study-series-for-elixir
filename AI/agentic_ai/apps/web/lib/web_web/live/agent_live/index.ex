defmodule WebWeb.AgentLive.Index do
  use WebWeb, :live_view

  alias Core.Contexts.Agents

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :agents, Agents.list_agents())}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    agent = Agents.get_agent!(id)
    {:ok, _} = Agents.delete_agent(agent)

    {:noreply,
     socket
     |> assign(:agents, Agents.list_agents())
     |> put_flash(:info, "에이전트가 삭제되었습니다.")}
  end

  @impl true
  def handle_event("toggle_status", %{"id" => id}, socket) do
    agent = Agents.get_agent!(id)

    {:ok, _} =
      case agent.status do
        :active -> Agents.disable_agent(agent)
        :disabled -> Agents.enable_agent(agent)
      end

    {:noreply, assign(socket, :agents, Agents.list_agents())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto p-6">
      <.header>
        에이전트 관리
        <:subtitle>Supervisor/Worker 에이전트를 생성하고 관리합니다.</:subtitle>
        <:actions>
          <.link navigate={~p"/admin/agents/new"} class="btn btn-primary gap-2">
            <.icon name="hero-plus" class="size-4" /> 새 에이전트
          </.link>
        </:actions>
      </.header>

      <div class="card bg-base-100 shadow overflow-x-auto">
        <table class="table table-zebra">
          <thead>
            <tr>
              <th>이름</th>
              <th>유형</th>
              <th>모델</th>
              <th>도구</th>
              <th>상태</th>
              <th class="w-40">작업</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={agent <- @agents}>
              <td>
                <div class="font-semibold">{agent.display_name || agent.name}</div>
                <div class="text-xs opacity-60">{agent.name}</div>
              </td>
              <td>
                <span class={["badge", agent_type_badge(agent.type)]}>{agent.type}</span>
              </td>
              <td class="text-xs">{agent.model}</td>
              <td class="text-xs">
                <%= if agent.enabled_tools == [] do %>
                  <span class="opacity-40">-</span>
                <% else %>
                  {Enum.join(agent.enabled_tools, ", ")}
                <% end %>
              </td>
              <td>
                <button
                  phx-click="toggle_status"
                  phx-value-id={agent.id}
                  class={["badge", agent_status_badge(agent.status)]}
                  title="클릭하여 상태 변경"
                >
                  {agent.status}
                </button>
              </td>
              <td>
                <div class="join">
                  <.link
                    navigate={~p"/admin/agents/#{agent.id}/edit"}
                    class="btn btn-ghost btn-xs join-item"
                  >
                    편집
                  </.link>
                  <button
                    phx-click="delete"
                    phx-value-id={agent.id}
                    data-confirm="삭제하시겠습니까?"
                    class="btn btn-ghost btn-xs text-error join-item"
                  >
                    삭제
                  </button>
                </div>
              </td>
            </tr>
            <tr :if={@agents == []}>
              <td colspan="6" class="text-center opacity-50 py-8">
                등록된 에이전트가 없습니다. 새 에이전트를 추가하세요.
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp agent_type_badge(:supervisor), do: "badge-primary"
  defp agent_type_badge(:worker), do: "badge-secondary"
  defp agent_type_badge(_), do: "badge-ghost"

  defp agent_status_badge(:active), do: "badge-success"
  defp agent_status_badge(:disabled), do: "badge-ghost"
  defp agent_status_badge(_), do: "badge-ghost"
end
