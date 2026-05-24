defmodule AgenticAiAgentWeb.Router do
  use AgenticAiAgentWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AgenticAiAgentWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug AgenticAiAgentWeb.Plugs.Locale
    plug AgenticAiAgentWeb.UserAuth, :fetch_current_user
  end

  pipeline :redirect_if_user_authenticated do
    plug AgenticAiAgentWeb.UserAuth, :redirect_if_user_authenticated
  end

  pipeline :require_authenticated_user do
    plug AgenticAiAgentWeb.UserAuth, :require_authenticated_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", AgenticAiAgentWeb do
    pipe_through :browser

    get "/locale/:locale", LocaleController, :set
    delete "/logout", UserSessionController, :delete
  end

  scope "/", AgenticAiAgentWeb do
    pipe_through [:browser, :redirect_if_user_authenticated]

    get "/register", UserRegistrationController, :new
    post "/register", UserRegistrationController, :create
    get "/login", UserSessionController, :new
    post "/login", UserSessionController, :create
  end

  scope "/", AgenticAiAgentWeb do
    pipe_through [:browser, :require_authenticated_user]

    put "/preferences/theme", PreferenceController, :theme

    live_session :authenticated,
      on_mount: [
        {AgenticAiAgentWeb.UserAuth, :ensure_authenticated},
        {AgenticAiAgentWeb.Locale, :default}
      ] do
      live "/", HomeLive, :index
      live "/profile", ProfileLive, :edit

      live "/cards", CardLive.Index, :index
      live "/cards/:id", CardLive.Show, :show
      live "/cards/:id/profile", CardLive.ProfileSettings, :edit
      live "/cards/:id/edit-source", CardLive.EditSource, :edit
      live "/cards/:id/history", CardLive.History, :index

      live "/chat", ChatLive
      live "/chat/:run_id", ChatLive

      live "/runs", RunLive.Index, :index
      live "/runs/:id", RunLive.Show, :show

      live "/insights", InsightsLive.Index, :index
      live "/improvements", ImprovementLive.Index, :index
      live "/feedback", FeedbackLive.Index, :index
      live "/notifications", NotificationLive.Index, :index

      live "/memories", MemoryLive.Index, :index

      live "/skills", SkillLive.Index, :index
      live "/skills/:slug/edit-source", SkillLive.EditSource, :edit
      live "/skills/:slug/history", SkillLive.History, :index

      live "/mcp", MCPLive.Index, :index
      live "/mcp/new", MCPLive.Form, :new
      live "/mcp/:id/edit", MCPLive.Form, :edit

      live "/evals", EvalLive.Index, :index
      live "/evals/:id", EvalLive.Show, :show

      live "/failures", FailureLive.Index, :index

      live "/tools", ToolLive.Index, :index
      live "/tools/:id/edit", ToolLive.Form, :edit
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", AgenticAiAgentWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:agentic_ai_agent, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: AgenticAiAgentWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
