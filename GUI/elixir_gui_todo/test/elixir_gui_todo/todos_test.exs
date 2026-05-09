defmodule ElixirGuiTodo.TodosTest do
  use ElixirGuiTodo.DataCase

  alias ElixirGuiTodo.Todos

  describe "todos" do
    test "creates, filters, toggles, and clears todos" do
      assert {:ok, first} = Todos.create_todo(%{"title" => "Ship desktop app"})
      assert {:ok, second} = Todos.create_todo(%{"title" => "Write release notes"})

      assert %{total: 2, active: 2, completed: 0} = Todos.count_by_state()
      assert Enum.map(Todos.list_todos(:active), & &1.id) == [second.id, first.id]

      assert {:ok, completed} = Todos.toggle_todo(first)
      assert completed.completed_at

      assert Enum.map(Todos.list_todos(:completed), & &1.id) == [first.id]
      assert %{total: 2, active: 1, completed: 1} = Todos.count_by_state()

      assert {1, nil} = Todos.clear_completed()
      assert Enum.map(Todos.list_todos(:all), & &1.id) == [second.id]
    end

    test "validates required title" do
      assert {:error, changeset} = Todos.create_todo(%{"title" => ""})
      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end
  end
end
