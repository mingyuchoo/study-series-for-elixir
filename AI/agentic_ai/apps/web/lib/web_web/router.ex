defmodule WebWeb.Router do
  use WebWeb, :router

  import WebWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {WebWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # 공개 라우트
  scope "/", WebWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # API
  scope "/api", WebWeb do
    pipe_through :api

    get "/health", HealthController, :index
  end

  # 비인증 사용자 전용 (로그인/회원가입)
  scope "/", WebWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live_session :redirect_if_user_is_authenticated,
      on_mount: [{WebWeb.UserAuth, :redirect_if_user_is_authenticated}] do
      live "/users/register", UserRegistrationLive, :new
      live "/users/log_in", UserLoginLive, :new
    end

    post "/users/log_in", UserSessionController, :create
  end

  # 인증 필수
  scope "/", WebWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{WebWeb.UserAuth, :ensure_authenticated}] do
      live "/chat", ChatLive, :index
      live "/chat/:id", ChatLive, :show
      live "/users/settings", UserSettingsLive, :edit

      live "/admin/agents", AgentLive.Index, :index
      live "/admin/agents/new", AgentLive.Form, :new
      live "/admin/agents/:id/edit", AgentLive.Form, :edit

      live "/admin/mcps", McpLive.Index, :index
      live "/admin/mcps/new", McpLive.Form, :new
      live "/admin/mcps/:id/edit", McpLive.Form, :edit

      live "/admin/rag", RagLive.Index, :index

      live "/admin/dashboard/home", DashboardHomeLive, :home
    end
  end

  # 로그아웃과 current_user mount (공용)
  scope "/", WebWeb do
    pipe_through [:browser]

    delete "/users/log_out", UserSessionController, :delete

    live_session :current_user, on_mount: [{WebWeb.UserAuth, :mount_current_user}] do
    end
  end

  # LiveDashboard (관리자)
  import Phoenix.LiveDashboard.Router

  scope "/admin" do
    pipe_through [:browser, :require_authenticated_user]

    live_dashboard "/dashboard",
      metrics: WebWeb.Telemetry,
      on_mount: [WebWeb.LiveDashboardCarbonStyle]
  end
end
