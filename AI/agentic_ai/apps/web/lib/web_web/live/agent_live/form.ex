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
    <div class="max-w-3xl mx-auto p-6">
      <div class="mb-6">
        <.link navigate={~p"/admin/agents"} class="link link-hover text-sm opacity-60">
          ← 에이전트 목록
        </.link>
        <h1 class="text-3xl font-bold mt-1">{@page_title}</h1>
      </div>

      <.form for={@form} phx-change="validate" phx-submit="save" class="space-y-4">
        <div class="grid grid-cols-2 gap-4">
          <div class="form-control">
            <label class="label"><span class="label-text">유형</span></label>
            <select
              name={@form[:type].name}
              class="select select-bordered w-full"
              value={@form[:type].value}
            >
              <option value="supervisor" selected={to_string(@form[:type].value) == "supervisor"}>
                supervisor
              </option>
              <option value="worker" selected={to_string(@form[:type].value) == "worker"}>
                worker
              </option>
            </select>
            <.errors field={@form[:type]} />
          </div>
          <div class="form-control">
            <label class="label"><span class="label-text">상태</span></label>
            <select
              name={@form[:status].name}
              class="select select-bordered w-full"
              value={@form[:status].value}
            >
              <option value="active" selected={to_string(@form[:status].value) == "active"}>
                active
              </option>
              <option value="disabled" selected={to_string(@form[:status].value) == "disabled"}>
                disabled
              </option>
            </select>
            <.errors field={@form[:status]} />
          </div>
        </div>

        <div class="form-control">
          <label class="label"><span class="label-text">내부 이름 (unique)</span></label>
          <input
            type="text"
            name={@form[:name].name}
            value={@form[:name].value}
            class="input input-bordered"
            placeholder="예: calculator_worker"
            required
          />
          <.errors field={@form[:name]} />
        </div>

        <div class="form-control">
          <label class="label"><span class="label-text">표시 이름</span></label>
          <input
            type="text"
            name={@form[:display_name].name}
            value={@form[:display_name].value}
            class="input input-bordered"
            placeholder="예: 계산 전문가"
          />
          <.errors field={@form[:display_name]} />
        </div>

        <div class="form-control">
          <label class="label"><span class="label-text">설명</span></label>
          <input
            type="text"
            name={@form[:description].name}
            value={@form[:description].value}
            class="input input-bordered"
          />
          <.errors field={@form[:description]} />
        </div>

        <div class="form-control">
          <label class="label"><span class="label-text">시스템 프롬프트</span></label>
          <textarea
            name={@form[:system_prompt].name}
            rows="8"
            class="textarea textarea-bordered font-mono text-xs"
          >{@form[:system_prompt].value}</textarea>
          <.errors field={@form[:system_prompt]} />
        </div>

        <div class="grid grid-cols-3 gap-4">
          <div class="form-control">
            <label class="label"><span class="label-text">모델</span></label>
            <input
              type="text"
              name={@form[:model].name}
              value={@form[:model].value}
              class="input input-bordered"
            />
            <.errors field={@form[:model]} />
          </div>
          <div class="form-control">
            <label class="label"><span class="label-text">Temperature (0-2)</span></label>
            <input
              type="number"
              step="0.1"
              min="0"
              max="2"
              name={@form[:temperature].name}
              value={@form[:temperature].value}
              class="input input-bordered"
            />
            <.errors field={@form[:temperature]} />
          </div>
          <div class="form-control">
            <label class="label"><span class="label-text">Max Iterations</span></label>
            <input
              type="number"
              min="1"
              max="50"
              name={@form[:max_iterations].name}
              value={@form[:max_iterations].value}
              class="input input-bordered"
            />
            <.errors field={@form[:max_iterations]} />
          </div>
        </div>

        <div class="form-control">
          <label class="label">
            <span class="label-text">활성 도구 (콤마 구분)</span>
          </label>
          <input
            type="text"
            name={@form[:enabled_tools].name}
            value={tools_string(@form[:enabled_tools].value)}
            class="input input-bordered"
            placeholder="calculator, web_search, get_current_time"
          />
          <.errors field={@form[:enabled_tools]} />
        </div>

        <div class="form-control">
          <label class="label"><span class="label-text">Config (JSON)</span></label>
          <textarea
            name={@form[:config].name}
            rows="3"
            class="textarea textarea-bordered font-mono text-xs"
          >{config_string(@form[:config].value)}</textarea>
          <.errors field={@form[:config]} />
        </div>

        <div class="flex gap-2 pt-4">
          <button type="submit" phx-disable-with="저장 중..." class="btn btn-primary">
            저장
          </button>
          <.link navigate={~p"/admin/agents"} class="btn btn-ghost">취소</.link>
        </div>
      </.form>
    </div>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true

  defp errors(assigns) do
    ~H"""
    <%= for {msg, opts} <- @field.errors do %>
      <div class="text-error text-sm mt-1">
        {Enum.reduce(opts, msg, fn {k, v}, acc -> String.replace(acc, "%{#{k}}", to_string(v)) end)}
      </div>
    <% end %>
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
