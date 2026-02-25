defmodule WebWeb.Router do
  use WebWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {WebWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", WebWeb do
    pipe_through :browser

    get "/", PageController, :home

    live "/chat", ChatLive, :index
    live "/chat/:id", ChatLive, :show
  end

  # API 라우트
  scope "/api", WebWeb do
    pipe_through :api

    # 헬스 체크
    get "/health", HealthController, :index
  end
end
