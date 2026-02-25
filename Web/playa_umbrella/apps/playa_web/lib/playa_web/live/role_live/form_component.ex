defmodule PlayaWeb.RoleLive.FormComponent do
  use PlayaWeb, :live_component

  alias Playa.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>Use this form to manage role records in your database.</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="role-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:name]} type="text" label="Name" placeholder="New role name" />
        <.input
          field={@form[:description]}
          type="text"
          label="Description"
          placeholder="Role description"
        />
        <:actions>
          <.button phx-disable-with="Saving..."><.icon name="hero-check" />Save</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{role: role} = assigns, socket) do
    changeset = Accounts.change_role(role)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"role" => role_params}, socket) do
    changeset =
      socket.assigns.role
      |> Accounts.change_role(role_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"role" => role_params}, socket) do
    save_role(socket, socket.assigns.action, role_params)
  end

  defp save_role(socket, :edit, role_params) do
    case Accounts.update_role(socket.assigns.role, role_params) do
      {:ok, role} ->
        notify_parent({:saved, role})

        {:noreply,
         socket
         |> put_flash(:info, "Role updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_role(socket, :new, role_params) do
    case Accounts.create_role(role_params) do
      {:ok, role} ->
        notify_parent({:saved, role})

        {:noreply,
         socket
         |> put_flash(:info, "Role created successfully")
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
