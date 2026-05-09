defmodule ElixirGuiTodoWeb.Router do
  use ElixirGuiTodoWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ElixirGuiTodoWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ElixirGuiTodoWeb do
    pipe_through :browser

    live "/", TodoLive
  end

  # Other scopes may use custom stacks.
  # scope "/api", ElixirGuiTodoWeb do
  #   pipe_through :api
  # end
end
