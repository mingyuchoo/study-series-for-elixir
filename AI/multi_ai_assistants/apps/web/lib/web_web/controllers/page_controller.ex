defmodule WebWeb.PageController do
  use WebWeb, :controller

  def home(conn, _params) do
    if conn.assigns[:current_user] do
      redirect(conn, to: ~p"/chat")
    else
      render(conn, :home)
    end
  end
end
