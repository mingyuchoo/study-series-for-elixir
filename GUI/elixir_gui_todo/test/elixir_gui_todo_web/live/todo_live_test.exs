defmodule ElixirGuiTodoWeb.TodoLiveTest do
  use ElixirGuiTodoWeb.ConnCase

  import Phoenix.LiveViewTest

  test "renders the todo workspace", %{conn: conn} do
    assert {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#todo-header")
    assert has_element?(view, "#todo-form")
    assert has_element?(view, "#todos")
  end

  test "creates and toggles a todo", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> form("#todo-form", todo: %{title: "Package desktop app", notes: "Linux first"})
    |> render_submit()

    assert has_element?(view, "#todos article", "Package desktop app")

    view
    |> element("[id^=toggle-todo-]")
    |> render_click()

    view
    |> element("#filter-completed")
    |> render_click()

    assert has_element?(view, "#todos article", "Package desktop app")
  end

  test "deletes a todo", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> form("#todo-form", todo: %{title: "Temporary task"})
    |> render_submit()

    assert has_element?(view, "#todos article", "Temporary task")

    view
    |> element("[id^=delete-todo-]")
    |> render_click()

    refute has_element?(view, "#todos article", "Temporary task")
  end
end
