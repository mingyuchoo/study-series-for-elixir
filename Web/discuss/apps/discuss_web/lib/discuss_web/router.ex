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
  end

  # 공개 경로
  scope "/", DiscussWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # 비인증 사용자 전용 경로 (로그인/회원가입)
  scope "/", DiscussWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/users/register", UserRegistrationController, :new
    post "/users/register", UserRegistrationController, :create
    get "/users/log_in", UserSessionController, :new
    post "/users/log_in", UserSessionController, :create
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

  # 로그아웃
  scope "/", DiscussWeb do
    pipe_through [:browser]

    delete "/users/log_out", UserSessionController, :delete
  end

  scope "/api", DiscussWeb do
    pipe_through :api
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
