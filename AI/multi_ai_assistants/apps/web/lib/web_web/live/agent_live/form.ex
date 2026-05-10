defmodule WebWeb.AgentLive.Form do
  use WebWeb, :live_view

  alias Core.Contexts.Agents
  alias Core.Schema.Agent

  @impl true
  def mount(params, _session, socket) do
    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    agent = %Agent{type: :worker, status: :active, enabled_tools: [], config: %{}}

    socket
    |> assign(:page_title, "새 에이전트")
    |> assign(:agent, agent)
    |> assign_form(Agents.change_agent(agent))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    agent = Agents.get_agent!(id)

    socket
    |> assign(:page_title, "에이전트 편집: #{agent.display_name || agent.name}")
    |> assign(:agent, agent)
    |> assign_form(Agents.change_agent(agent))
  end

  @impl true
  def handle_event("validate", %{"agent" => params}, socket) do
    changeset =
      socket.assigns.agent
      |> Agents.change_agent(normalize(params))
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  @impl true
  def handle_event("save", %{"agent" => params}, socket) do
    save_agent(socket, socket.assigns.live_action, normalize(params))
  end

  defp save_agent(socket, :new, params) do
    case Agents.create_agent(params) do
      {:ok, _agent} ->
        {:noreply,
         socket
         |> put_flash(:info, "에이전트가 생성되었습니다.")
         |> push_navigate(to: ~p"/admin/agents")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_agent(socket, :edit, params) do
    case Agents.update_agent(socket.assigns.agent, params) do
      {:ok, _agent} ->
        {:noreply,
         socket
         |> put_flash(:info, "에이전트가 수정되었습니다.")
         |> push_navigate(to: ~p"/admin/agents")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp normalize(params) do
    params
    |> Map.update("enabled_tools", [], fn
      tools when is_binary(tools) ->
        tools |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

      tools when is_list(tools) ->
        tools

      _ ->
        []
    end)
    |> Map.update("config", %{}, fn
      v when is_binary(v) ->
        case Jason.decode(v) do
          {:ok, map} when is_map(map) -> map
          _ -> %{}
        end

      v when is_map(v) ->
        v

      _ ->
        %{}
    end)
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-3xl bg-base-100 p-6">
      <div class="mb-6 border-b border-base-300 pb-6">
        <.link navigate={~p"/admin/agents"} class="link link-primary text-sm">
          ← 에이전트 목록
        </.link>
        <h1 class="mt-3 text-4xl font-light leading-tight">{@page_title}</h1>
      </div>

      <div class="card bg-base-100">
        <div class="card-body">
          <.form for={@form} phx-change="validate" phx-submit="save">
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <.input
                field={@form[:type]}
                type="select"
                label="유형"
                options={[{"supervisor", "supervisor"}, {"worker", "worker"}]}
              />
              <.input
                field={@form[:status]}
                type="select"
                label="상태"
                options={[{"active", "active"}, {"disabled", "disabled"}]}
              />
            </div>

            <.input
              field={@form[:name]}
              type="text"
              label="내부 이름 (unique)"
              placeholder="예: calculator_worker"
              required
            />

            <.input
              field={@form[:display_name]}
              type="text"
              label="표시 이름"
              placeholder="예: 계산 전문가"
            />

            <.input field={@form[:description]} type="text" label="설명" />

            <.input
              field={@form[:avatar_path]}
              type="text"
              label="아바타 파일"
              placeholder="avatar-07.png"
            />

            <.input
              field={@form[:system_prompt]}
              type="textarea"
              label="시스템 프롬프트"
              rows="8"
              class="w-full textarea font-mono text-xs"
            />

            <div class="grid grid-cols-1 sm:grid-cols-3 gap-3">
              <.input field={@form[:model]} type="text" label="모델" />
              <.input
                field={@form[:temperature]}
                type="number"
                label="Temperature (0-2)"
                step="0.1"
                min="0"
                max="2"
              />
              <.input
                field={@form[:max_iterations]}
                type="number"
                label="Max Iterations"
                min="1"
                max="50"
              />
            </div>

            <.input
              field={@form[:enabled_tools]}
              type="text"
              label="활성 도구 (콤마 구분)"
              value={tools_string(@form[:enabled_tools].value)}
              placeholder="calculator, web_search, get_current_time"
            />

            <.input
              field={@form[:config]}
              type="textarea"
              label="Config (JSON)"
              rows="3"
              value={config_string(@form[:config].value)}
              class="w-full textarea font-mono text-xs"
            />

            <div class="flex gap-2 pt-4">
              <button type="submit" phx-disable-with="저장 중..." class="btn btn-primary">
                저장
              </button>
              <.link navigate={~p"/admin/agents"} class="btn btn-ghost">취소</.link>
            </div>
          </.form>
        </div>
      </div>
    </div>
    """
  end

  defp tools_string(nil), do: ""
  defp tools_string(list) when is_list(list), do: Enum.join(list, ", ")
  defp tools_string(str) when is_binary(str), do: str
  defp tools_string(_), do: ""

  defp config_string(nil), do: ""
  defp config_string(map) when is_map(map), do: Jason.encode!(map, pretty: true)
  defp config_string(str) when is_binary(str), do: str
  defp config_string(_), do: ""
end
