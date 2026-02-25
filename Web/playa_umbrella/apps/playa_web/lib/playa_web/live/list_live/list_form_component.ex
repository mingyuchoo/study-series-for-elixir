defmodule PlayaWeb.ListLive.ListFormComponent do
  alias Productivity.ActivityLog
  use PlayaWeb, :live_component

  alias Productivity.Works

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>Use list to grouping items with a common theme.</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="list-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.label>ID</.label>
        <span class="px-3 pt-8 text-sm text-zinc-400">
          #{@list.id}
        </span>
        <.input field={@form[:title]} type="text" label="Title" placeholder="New list title" />
        <.label>Total items</.label>
        <span class="px-3 pt-8 text-sm text-zinc-400">
          {@list.item_count} EA
        </span>
        <.label>Inserted at</.label>
        <span class="px-3 pt-8 text-sm text-zinc-400">
          {(@list.inserted_at && Timex.format!(@list.inserted_at, "%F %T", :strftime)) || "NEW"}
        </span>
        <.label>Updated at</.label>
        <span class="px-3 pt-8 text-sm text-zinc-400">
          {(@list.updated_at && Timex.format!(@list.updated_at, "%F %T", :strftime)) || "NEW"}
        </span>
        <.label>Owned by</.label>
        <span class="px-3 pt-8 text-sm text-zinc-400">
          {(@list.user_id && (@list.user.nickname || @list.user.id)) ||
            (@scope.current_user.nickname || @scope.current_user_id)}
        </span>
        <:actions>
          <.button phx-disable-with="Saving..."><.icon name="hero-check" />Save</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @doc """
  IMPORTANT:
  index.html.heex 데이터를 컴포넌트에 전달하는데 사용
  """
  @impl true
  def update(%{list: list, scope: scope} = assigns, socket) do
    changeset = Works.change_list(list)

    {:ok,
     socket
     |> assign(assigns)
     # Scope를 소켓에 전달
     |> assign(:scope, scope)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"list" => list_params}, socket) do
    changeset =
      socket.assigns.list
      |> Works.change_list(list_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"list" => list_params}, socket) do
    save_list(socket, socket.assigns.action, list_params)
  end

  defp save_list(socket, :list_edit, list_params) do
    case Works.update_list(socket.assigns.list, list_params) do
      {:ok, list} ->
        ActivityLog.log(socket.assigns.scope, list, %{action: "save:list_edit"})
        notify_parent({:saved, list})

        {:noreply,
         socket
         |> put_flash(:info, "List updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_list(socket, :list_new, list_params) do
    list_params
    # IMPORTANT:
    # 보안 목적으로 render에서 처리하지 않고
    # 함수 안에서 user_id를 넣음
    |> Map.put("user_id", socket.assigns.scope.current_user_id)
    |> Works.create_list()
    |> case do
      {:ok, list} ->
        ActivityLog.log(socket.assigns.scope, list, %{action: "save:list_new"})
        notify_parent({:saved, list})

        {:noreply,
         socket
         |> put_flash(:info, "List created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
