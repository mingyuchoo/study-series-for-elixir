defmodule ElixirGuiTodoWeb.PageController do
  use ElixirGuiTodoWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
