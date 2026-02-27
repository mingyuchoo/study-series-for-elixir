defmodule DiscussWeb.Router do
  use DiscussWeb, :router

  import DiscussWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {DiscussWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :fetch_api_user
  end

  pipeline :admin_auth do
    plug :require_admin_user
  end

  pipeline :api_auth do
    plug :require_api_user
  end

  # 공개 경로
  scope "/", DiscussWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # 비인증 사용자 전용 경로 (로그인/회원가입/비밀번호 재설정/이메일 인증)
  scope "/", DiscussWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/users/register", UserRegistrationController, :new
    post "/users/register", UserRegistrationController, :create
    get "/users/log_in", UserSessionController, :new
    post "/users/log_in", UserSessionController, :create
    get "/users/reset_password", UserPasswordResetController, :new
    post "/users/reset_password", UserPasswordResetController, :create
    get "/users/reset_password/:token", UserPasswordResetController, :edit
    put "/users/reset_password/:token", UserPasswordResetController, :update
  end

  # 이메일 인증 (인증 여부에 무관하게 접근 가능)
  scope "/", DiscussWeb do
    pipe_through :browser

    get "/users/confirm", UserConfirmationController, :new
    post "/users/confirm", UserConfirmationController, :create
    get "/users/confirm/:token", UserConfirmationController, :edit
    post "/users/confirm/:token", UserConfirmationController, :update
  end

  # 인증 필수 경로
  scope "/", DiscussWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/topics", TopicController, :index
    get "/topics/new", TopicController, :new
    post "/topics", TopicController, :create
    get "/topics/:id", TopicController, :show
    get "/topics/:id/edit", TopicController, :edit
    put "/topics/:id", TopicController, :update
    delete "/topics/:id", TopicController, :delete
  end

  # 관리자 전용 경로
  scope "/admin", DiscussWeb do
    pipe_through [:browser, :require_authenticated_user, :admin_auth]

    resources "/users", AdminUserController
  end

  # 로그아웃
  scope "/", DiscussWeb do
    pipe_through [:browser]

    delete "/users/log_out", UserSessionController, :delete
  end

  # JSON API - 공개
  scope "/api", DiscussWeb.Api do
    pipe_through :api

    get "/topics", TopicController, :index
    get "/topics/:id", TopicController, :show
  end

  # JSON API - 인증 필요
  scope "/api", DiscussWeb.Api do
    pipe_through [:api, :api_auth]

    post "/topics", TopicController, :create
    put "/topics/:id", TopicController, :update
    delete "/topics/:id", TopicController, :delete
  end

  if Application.compile_env(:discuss_web, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: DiscussWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
