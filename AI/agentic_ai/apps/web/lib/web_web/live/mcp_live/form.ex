defmodule WebWeb.McpLive.Form do
  use WebWeb, :live_view

  alias Core.Contexts.Mcps
  alias Core.Schema.Mcp

  @impl true
  def mount(params, _session, socket) do
    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    mcp = %Mcp{args: [], env: %{}, enabled: true}

    socket
    |> assign(:page_title, "새 MCP")
    |> assign(:mcp, mcp)
    |> assign_form(Mcps.change_mcp(mcp))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    mcp = Mcps.get_mcp!(id)

    socket
    |> assign(:page_title, "MCP 편집: #{mcp.name}")
    |> assign(:mcp, mcp)
    |> assign_form(Mcps.change_mcp(mcp))
  end

  @impl true
  def handle_event("validate", %{"mcp" => params}, socket) do
    changeset =
      socket.assigns.mcp
      |> Mcps.change_mcp(normalize(params))
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  @impl true
  def handle_event("save", %{"mcp" => params}, socket) do
    save_mcp(socket, socket.assigns.live_action, normalize(params))
  end

  defp save_mcp(socket, :new, params) do
    case Mcps.create_mcp(params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "MCP가 생성되었습니다.")
         |> push_navigate(to: ~p"/admin/mcps")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_mcp(socket, :edit, params) do
    case Mcps.update_mcp(socket.assigns.mcp, params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "MCP가 수정되었습니다.")
         |> push_navigate(to: ~p"/admin/mcps")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp normalize(params) do
    params
    |> Map.update("args", [], fn
      v when is_binary(v) ->
        v |> String.split(~r/\s+/, trim: true)

      v when is_list(v) ->
        v

      _ ->
        []
    end)
    |> Map.update("env", %{}, fn
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
    <div class="max-w-2xl mx-auto p-6">
      <div class="mb-6">
        <.link navigate={~p"/admin/mcps"} class="link link-hover text-sm opacity-60">
          ← MCP 목록
        </.link>
        <h1 class="text-3xl font-bold mt-1">{@page_title}</h1>
      </div>

      <.form for={@form} phx-change="validate" phx-submit="save" class="space-y-4">
        <div class="form-control">
          <label class="label"><span class="label-text">이름 (unique)</span></label>
          <input
            type="text"
            name={@form[:name].name}
            value={@form[:name].value}
            class="input input-bordered"
            placeholder="예: firecrawl"
            required
          />
          <.errors field={@form[:name]} />
        </div>

        <div class="form-control">
          <label class="label"><span class="label-text">실행 명령</span></label>
          <input
            type="text"
            name={@form[:command].name}
            value={@form[:command].value}
            class="input input-bordered font-mono"
            placeholder="예: npx"
            required
          />
          <.errors field={@form[:command]} />
        </div>

        <div class="form-control">
          <label class="label">
            <span class="label-text">인자 (공백 구분)</span>
          </label>
          <input
            type="text"
            name={@form[:args].name}
            value={args_string(@form[:args].value)}
            class="input input-bordered font-mono"
            placeholder="-y firecrawl-mcp"
          />
          <.errors field={@form[:args]} />
        </div>

        <div class="form-control">
          <label class="label">
            <span class="label-text">환경 변수 (JSON)</span>
          </label>
          <textarea
            name={@form[:env].name}
            rows="4"
            class="textarea textarea-bordered font-mono text-xs"
          >{env_string(@form[:env].value)}</textarea>
          <div class="label">
            <span class="label-text-alt opacity-60">
              {"${VAR_NAME} 형식으로 시스템 환경변수 참조 가능 (예: {\"API_KEY\": \"${FIRECRAWL_API_KEY}\"})"}
            </span>
          </div>
          <.errors field={@form[:env]} />
        </div>

        <div class="form-control">
          <label class="label cursor-pointer justify-start gap-2">
            <input
              type="hidden"
              name={@form[:enabled].name}
              value="false"
            />
            <input
              type="checkbox"
              name={@form[:enabled].name}
              value="true"
              checked={@form[:enabled].value in [true, "true"]}
              class="checkbox"
            />
            <span class="label-text">활성화</span>
          </label>
        </div>

        <div class="flex gap-2 pt-4">
          <button type="submit" phx-disable-with="저장 중..." class="btn btn-primary">저장</button>
          <.link navigate={~p"/admin/mcps"} class="btn btn-ghost">취소</.link>
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

  defp args_string(nil), do: ""
  defp args_string(list) when is_list(list), do: Enum.join(list, " ")
  defp args_string(s) when is_binary(s), do: s
  defp args_string(_), do: ""

  defp env_string(nil), do: "{}"
  defp env_string(map) when is_map(map), do: Jason.encode!(map, pretty: true)
  defp env_string(s) when is_binary(s), do: s
  defp env_string(_), do: "{}"
end
