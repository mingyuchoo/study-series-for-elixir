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
      <div class="flex items-center justify-between mb-6">
        <div>
          <h1 class="text-3xl font-bold">에이전트 관리</h1>
          <p class="text-base-content/60">Supervisor/Worker 에이전트를 생성하고 관리합니다.</p>
        </div>
        <.link navigate={~p"/admin/agents/new"} class="btn btn-primary gap-2">
          <.icon name="hero-plus" class="w-4 h-4" /> 새 에이전트
        </.link>
      </div>

      <div class="overflow-x-auto bg-base-100 rounded-lg shadow">
        <table class="table">
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
            <%= for agent <- @agents do %>
              <tr>
                <td>
                  <div class="font-semibold">{agent.display_name || agent.name}</div>
                  <div class="text-xs opacity-60">{agent.name}</div>
                </td>
                <td>
                  <span class={[
                    "badge",
                    agent.type == :supervisor && "badge-primary",
                    agent.type == :worker && "badge-secondary"
                  ]}>
                    {agent.type}
                  </span>
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
                    class={[
                      "badge",
                      agent.status == :active && "badge-success",
                      agent.status == :disabled && "badge-ghost"
                    ]}
                  >
                    {agent.status}
                  </button>
                </td>
                <td>
                  <div class="flex gap-1">
                    <.link
                      navigate={~p"/admin/agents/#{agent.id}/edit"}
                      class="btn btn-ghost btn-xs"
                    >
                      편집
                    </.link>
                    <button
                      phx-click="delete"
                      phx-value-id={agent.id}
                      data-confirm="삭제하시겠습니까?"
                      class="btn btn-ghost btn-xs text-error"
                    >
                      삭제
                    </button>
                  </div>
                </td>
              </tr>
            <% end %>
            <%= if @agents == [] do %>
              <tr>
                <td colspan="6" class="text-center opacity-50 py-8">
                  등록된 에이전트가 없습니다. 새 에이전트를 추가하세요.
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
    """
  end
end
