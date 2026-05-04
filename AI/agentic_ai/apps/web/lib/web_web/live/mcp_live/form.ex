defmodule WebWeb.McpLive.Form do
  use WebWeb, :live_view

  alias Core.Contexts.Mcps
  alias Core.Schema.Mcp

  @impl true
  def mount(params, _session, socket) do
    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    mcp = %Mcp{args: [], env: %{}, enabled: true, local_permission_level: :none}

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
    |> Map.update("local_permission_level", "none", fn
      v when is_atom(v) -> Atom.to_string(v)
      v when is_binary(v) -> v
      _ -> "none"
    end)
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-2xl bg-base-100 p-6">
      <div class="mb-6 border-b border-base-300 pb-6">
        <.link navigate={~p"/admin/mcps"} class="link link-primary text-sm">
          ← MCP 목록
        </.link>
        <h1 class="mt-3 text-4xl font-light leading-tight">{@page_title}</h1>
      </div>

      <div class="card bg-base-100">
        <div class="card-body">
          <.form for={@form} phx-change="validate" phx-submit="save">
            <.input
              field={@form[:name]}
              type="text"
              label="이름 (unique)"
              placeholder="예: firecrawl"
              required
            />

            <.input
              field={@form[:command]}
              type="text"
              label="실행 명령"
              placeholder="예: npx"
              class="w-full input font-mono"
              required
            />

            <.input
              field={@form[:args]}
              type="text"
              label="인자 (공백 구분)"
              value={args_string(@form[:args].value)}
              class="w-full input font-mono"
              placeholder="-y firecrawl-mcp"
            />

            <.input
              field={@form[:env]}
              type="textarea"
              label="환경 변수 (JSON)"
              rows="4"
              value={env_string(@form[:env].value)}
              class="w-full textarea font-mono text-xs"
            />
            <p class="text-xs opacity-60 -mt-1 mb-2">
              {~s[${VAR_NAME} 형식으로 시스템 환경변수 참조 가능 (예: {"API_KEY": "${FIRECRAWL_API_KEY}"})]}
            </p>

            <.input
              field={@form[:local_permission_level]}
              type="select"
              label="로컬 권한 위임 수준"
              options={local_permission_options()}
            />
            <p class="text-xs opacity-60 -mt-1 mb-2">
              Filesystem/Desktop Commander처럼 로컬 파일 또는 터미널 권한을 위임하는 MCP에 적용할 정책 수준입니다.
            </p>

            <.input field={@form[:enabled]} type="checkbox" label="활성화" />

            <div class="flex gap-2 pt-4">
              <button type="submit" phx-disable-with="저장 중..." class="btn btn-primary">
                저장
              </button>
              <.link navigate={~p"/admin/mcps"} class="btn btn-ghost">취소</.link>
            </div>
          </.form>
        </div>
      </div>
    </div>
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

  defp local_permission_options do
    [
      {"없음", :none},
      {"읽기 전용", :read_only},
      {"워크스페이스", :workspace},
      {"전체 권한", :full}
    ]
  end
end
