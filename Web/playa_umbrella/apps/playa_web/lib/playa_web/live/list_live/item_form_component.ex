defmodule PlayaWeb.ListLive.ItemFormComponent do
  alias Productivity.ActivityLog
  use PlayaWeb, :live_component

  alias Productivity.Works

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title} for {@list.title}
        <:subtitle>Create item to implement and apply it to your life.</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="item-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <!-- NOTE: list_id 는 넘어온 list.id 로 미리 지정해 놓음 -->
        <.label>ID</.label>
        <span class="px-3 pt-8 text-sm text-zinc-400">
          #{@item.id}
        </span>
        <.input field={@form[:list_id]} type="hidden" value={@list.id} />
        <.input field={@form[:title]} type="text" label="Title" placeholder="New item title" />
        <.input
          field={@form[:description]}
          type="textarea"
          label="Description"
          placeholder="describe here"
        />
        <.radio_group
          field={@form[:status]}
          options={Enum.map(@status_values, fn status -> {Atom.to_string(status), status} end)}
          label="Status"
        />
        <.label>Inserted at</.label>
        <span class="px-3 pt-8 text-sm text-zinc-400">
          {(@item.inserted_at && Timex.format!(@item.inserted_at, "%F %T", :strftime)) || "NEW"}
        </span>
        <.label>Updated at</.label>
        <span class="px-3 pt-8 text-sm text-zinc-400">
          {(@item.updated_at && Timex.format!(@item.updated_at, "%F %T", :strftime)) || "NEW"}
        </span>
        <.label>Owned by</.label>
        <span class="px-3 pt-8 text-sm text-zinc-400">
          <%= if @item.user.__struct__ == Ecto.Association.NotLoaded do %>
            {@scope.current_user.nickname || "##{@scope.current_user.id}"}
          <% else %>
            {@item.user.nickname || "##{@item.user.id}"}
          <% end %>
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
  def update(%{item: item, scope: scope} = assigns, socket) do
    changeset = Works.change_item(item)
    # 모든 리스트를 가져옴
    lists = Works.list_lists()
    status_values = Works.Item.status_values()

    {:ok,
     socket
     |> assign(assigns)
     # Scope를 소켓에 전달
     |> assign(:scope, scope)
     # 리스트 데이터를 소켓에 할당
     |> assign(:lists, lists)
     |> assign(:status_values, status_values)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"item" => item_params}, socket) do
    changeset =
      socket.assigns.item
      |> Works.change_item(item_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"item" => item_params}, socket) do
    save_item(socket, socket.assigns.action, item_params)
  end

  defp save_item(socket, :item_edit, item_params) do
    case Works.update_item(socket.assigns.item, item_params) do
      {:ok, item} ->
        ActivityLog.log(socket.assigns.scope, item, %{action: "save:item_edit"})
        notify_parent({:saved, item})

        {:noreply,
         socket
         |> put_flash(:info, "Item updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_item(socket, :item_new, item_params) do
    item_params
    # IMPORTANT:
    # 보안 목적으로 redner에서 처리하지 않고
    # 함수 안에서 usre_id를 넣음
    |> Map.put("user_id", socket.assigns.scope.current_user_id)
    |> Works.create_item()
    |> case do
      {:ok, item} ->
        ActivityLog.log(socket.assigns.scope, item, %{action: "save:item_new"})

        item_params["list_id"]
        |> Works.get_list!()
        |> Works.increase_item_count()

        notify_parent({:saved, item})

        {:noreply,
         socket
         |> put_flash(:info, "Item created successfully")
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
