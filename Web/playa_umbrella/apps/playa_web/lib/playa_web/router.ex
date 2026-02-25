defmodule PlayaWeb.Router do
  use PlayaWeb, :router

  import PlayaWeb.UserAuth

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {PlayaWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
    plug(:fetch_current_user)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  pipeline :auth do
    plug(Auth.GuardianPipelineMaybe)
  end

  scope "/", PlayaWeb do
    pipe_through(:browser)

    get("/", HomeController, :index)
    get("/components", HomeController, :components)
  end

  scope "/api", PlayaWeb do
    pipe_through([:api, :auth])

    get("/health-check", HealthCheckController, :index)
    get("/get_token", AuthController, :get_token)
    get("/me", AuthController, :me)
    get("/delete", AuthController, :delete)
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:playa_web, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through(:browser)

      live_dashboard("/dashboard", metrics: PlayaWeb.Telemetry)
      forward("/mailbox", Plug.Swoosh.MailboxPreview)
    end
  end

  ## Authentication routes

  scope "/", PlayaWeb do
    pipe_through([:browser, :redirect_if_user_is_authenticated])

    live_session :redirect_if_user_is_authenticated,
      on_mount: [{PlayaWeb.UserAuth, :redirect_if_user_is_authenticated}] do
      live("/users/register", UserLive.Registration, :new)
      live("/users/log_in", UserLive.Login, :new)
      live("/users/reset_password", UserLive.ForgotPassword, :new)
      live("/users/reset_password/:token", UserLive.ResetPassword, :edit)
    end

    post("/users/log_in", UserSessionController, :create)
  end

  scope "/", PlayaWeb do
    pipe_through([:browser, :require_authenticated_user])

    live_session :require_authenticated_user,
      on_mount: [{PlayaWeb.UserAuth, :ensure_authenticated}, PlayaWeb.Scope] do
      live("/counter", CounterLive.Index, :index)

      live("/users/settings", UserLive.Settings, :edit)
      live("/users/settings/confirm_email/:token", UserLive.Settings, :confirm_email)

      live("/works/lists", ListLive.ListIndex, :list_index)
      live("/works/lists/new", ListLive.ListIndex, :list_new)
      live("/works/lists/:list_id/edit", ListLive.ListIndex, :list_edit)
      live("/works/lists/:list_id", ListLive.ListShow, :list_show)
      live("/works/lists/:list_id/show/edit", ListLive.ListShow, :list_edit)
      live("/works/lists/:list_id/items/new", ListLive.ListShow, :item_new)
      live("/works/lists/:list_id/items/:item_id/edit", ListLive.ListShow, :item_edit)

      live("/accounts/roles", RoleLive.Index, :index)
      live("/accounts/roles/new", RoleLive.Index, :new)
      live("/accounts/roles/:role_id/edit", RoleLive.Index, :edit)
      live("/accounts/roles/:role_id", RoleLive.Show, :show)
      live("/accounts/roles/:role_id/show/edit", RoleLive.Show, :edit)

      live("/accounts/users", UserLive.Index, :index)
      live("/accounts/users/new", UserLive.Index, :new)
      live("/accounts/users/:user_id/edit", UserLive.Index, :edit)
      live("/accounts/users/:user_id", UserLive.Show, :show)
      live("/accounts/users/:user_id/show/edit", UserLive.Show, :edit)
    end
  end

  scope "/", PlayaWeb do
    pipe_through([:browser])

    delete("/users/log_out", UserSessionController, :delete)

    live_session :current_user,
      on_mount: [{PlayaWeb.UserAuth, :mount_current_user}] do
      live("/users/confirm/:token", UserLive.Confirmation, :edit)
      live("/users/confirm", UserLive.ConfirmationInstructions, :new)
    end
  end
end
