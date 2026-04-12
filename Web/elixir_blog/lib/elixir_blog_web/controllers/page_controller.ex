defmodule ElixirBlogWeb.PageController do
  use ElixirBlogWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
