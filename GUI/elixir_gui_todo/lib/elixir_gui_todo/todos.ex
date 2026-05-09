defmodule ElixirGuiTodo.Todos do
  @moduledoc """
  Todo list data access and mutations.
  """

  import Ecto.Query

  alias ElixirGuiTodo.Repo
  alias ElixirGuiTodo.Todos.Todo

  def list_todos(filter \\ :all)

  def list_todos(:active) do
    Todo
    |> where([todo], is_nil(todo.completed_at))
    |> order_query()
    |> Repo.all()
  end

  def list_todos(:completed) do
    Todo
    |> where([todo], not is_nil(todo.completed_at))
    |> order_query()
    |> Repo.all()
  end

  def list_todos(:all) do
    Todo
    |> order_query()
    |> Repo.all()
  end

  def count_by_state do
    %{total: total, active: active, completed: completed} = %{
      total: Repo.aggregate(Todo, :count),
      active: Todo |> where([todo], is_nil(todo.completed_at)) |> Repo.aggregate(:count),
      completed: Todo |> where([todo], not is_nil(todo.completed_at)) |> Repo.aggregate(:count)
    }

    %{total: total, active: active, completed: completed}
  end

  def get_todo!(id), do: Repo.get!(Todo, id)

  def change_todo(%Todo{} = todo, attrs \\ %{}) do
    Todo.changeset(todo, attrs)
  end

  def create_todo(attrs) do
    %Todo{}
    |> Todo.changeset(attrs)
    |> Repo.insert()
  end

  def update_todo(%Todo{} = todo, attrs) do
    todo
    |> Todo.changeset(attrs)
    |> Repo.update()
  end

  def toggle_todo(%Todo{completed_at: nil} = todo) do
    todo
    |> Ecto.Changeset.change(completed_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.update()
  end

  def toggle_todo(%Todo{} = todo) do
    todo
    |> Ecto.Changeset.change(completed_at: nil)
    |> Repo.update()
  end

  def delete_todo(%Todo{} = todo), do: Repo.delete(todo)

  def clear_completed do
    Todo
    |> where([todo], not is_nil(todo.completed_at))
    |> Repo.delete_all()
  end

  defp order_query(query) do
    from todo in query,
      order_by: [
        asc: fragment("? IS NOT NULL", todo.completed_at),
        desc: todo.inserted_at,
        desc: todo.id
      ]
  end
end
