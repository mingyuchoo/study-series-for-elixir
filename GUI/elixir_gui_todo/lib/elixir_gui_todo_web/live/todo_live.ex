defmodule ElixirGuiTodoWeb.TodoLive do
  use ElixirGuiTodoWeb, :live_view

  alias ElixirGuiTodo.Todos
  alias ElixirGuiTodo.Todos.Todo

  @filters [:all, :active, :completed]

  @impl true
  def mount(_params, _session, socket) do
    filter = :all
    todos = Todos.list_todos(filter)

    {:ok,
     socket
     |> assign(:page_title, "Elixir Todo")
     |> assign(:filter, filter)
     |> assign(:counts, Todos.count_by_state())
     |> assign(:empty?, todos == [])
     |> assign(:form, to_form(Todos.change_todo(%Todo{})))
     |> stream(:todos, todos)}
  end

  @impl true
  def handle_event("save", %{"todo" => todo_params}, socket) do
    case Todos.create_todo(todo_params) do
      {:ok, _todo} ->
        {:noreply,
         socket
         |> put_flash(:info, "Todo added")
         |> assign(:form, to_form(Todos.change_todo(%Todo{})))
         |> refresh_todos()}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("toggle", %{"id" => id}, socket) do
    id
    |> Todos.get_todo!()
    |> Todos.toggle_todo()

    {:noreply, refresh_todos(socket)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    id
    |> Todos.get_todo!()
    |> Todos.delete_todo()

    {:noreply, refresh_todos(socket)}
  end

  def handle_event("clear_completed", _params, socket) do
    Todos.clear_completed()
    {:noreply, refresh_todos(socket)}
  end

  def handle_event("filter", %{"filter" => filter}, socket) do
    filter = parse_filter(filter)
    {:noreply, socket |> assign(:filter, filter) |> refresh_todos()}
  end

  defp refresh_todos(socket) do
    todos = Todos.list_todos(socket.assigns.filter)

    socket
    |> assign(:counts, Todos.count_by_state())
    |> assign(:empty?, todos == [])
    |> stream(:todos, todos, reset: true)
  end

  defp parse_filter(filter) do
    filter = String.to_existing_atom(filter)

    if filter in @filters do
      filter
    else
      :all
    end
  rescue
    ArgumentError -> :all
  end

  defp filter_label(:all), do: "All"
  defp filter_label(:active), do: "Active"
  defp filter_label(:completed), do: "Done"

  defp completed?(%Todo{completed_at: completed_at}), do: not is_nil(completed_at)
end
