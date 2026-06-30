defmodule TugasWeb.Router do
  use TugasWeb, :router

  import TugasWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_cookies
    plug :fetch_live_flash
    plug :put_root_layout, html: {TugasWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
    plug TugasWeb.Plugs.FilterSession
    plug TugasWeb.Locale
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", TugasWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/locale/:locale", LocaleController, :update
  end

  # App API — pairing exchange (unauthenticated: the pairing code IS the credential).
  scope "/api", TugasWeb.Api, as: :api do
    pipe_through :api

    post "/pair", PairController, :create
  end

  # App API (token-authenticated).
  scope "/api", TugasWeb.Api, as: :api do
    pipe_through [:api, TugasWeb.Plugs.ApiTokenAuth]

    post "/entities/:slug/todos", TodoController, :create
  end

  # Enable Swoosh mailbox preview in development
  if Application.compile_env(:tugas, :dev_routes) do
    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", TugasWeb do
    pipe_through [:browser, :require_authenticated_user, TugasWeb.Plugs.AutoRouteByDevice]

    live_session :require_authenticated_user,
      on_mount: [{TugasWeb.UserAuth, :require_authenticated}, {TugasWeb.Locale, :default}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
      live "/entities", EntityLive.Select, :index
    end

    live_session :entity_scoped,
      on_mount: [
        {TugasWeb.UserAuth, :require_authenticated},
        {TugasWeb.UserAuth, :require_entity},
        {TugasWeb.Locale, :default}
      ] do
      live "/entities/:entity_slug", DashboardLive.Index, :index
      live "/entities/:entity_slug/duties", DutyLive.Index, :index
      live "/entities/:entity_slug/duties/new", DashboardLive.Index, :new
      live "/entities/:entity_slug/duties/:id", DutyLive.Show, :show
      live "/entities/:entity_slug/duty-types", DutyTypeLive.Index, :index
      live "/entities/:entity_slug/members", MembershipLive.Index, :index
      live "/entities/:entity_slug/invite-session/:role", MembershipLive.InviteSession, :show
      live "/entities/:entity_slug/todos/team-log", TodoLive.TeamLog, :index
      live "/entities/:entity_slug/todos", TodoLive.Index, :index

      live "/m/:entity_slug", MobileLive.Dashboard, :index
      live "/m/:entity_slug/duties", MobileLive.DutyIndex, :index
      live "/m/:entity_slug/duties/new", MobileLive.Dashboard, :new
      live "/m/:entity_slug/duties/:id", MobileLive.DutyShow, :show
      live "/m/:entity_slug/duty-types", MobileLive.DutyTypes, :index
      live "/m/:entity_slug/todos/team-log", MobileLive.TodoTeamLog, :index
      live "/m/:entity_slug/todos", MobileLive.Todos, :index
      live "/m/:entity_slug/todos/new", MobileLive.Todos, :new
      live "/m/:entity_slug/members", MobileLive.Members, :index
      live "/m/:entity_slug/invite-session/:role", MobileLive.InviteSession, :show
    end

    live_session :entity_connect_app,
      on_mount: [
        {TugasWeb.UserAuth, :require_authenticated},
        {TugasWeb.UserAuth, :require_entity},
        {TugasWeb.UserAuth, :require_sudo_mode},
        {TugasWeb.Locale, :default}
      ] do
      live "/entities/:entity_slug/connect-app", ConnectAppLive.Show, :show
    end

    post "/users/update-password", UserSessionController, :update_password

    get "/view-mode", ViewModeController, :set
    get "/set-view", ViewModeController, :set

    get "/entities/:entity_slug/duties/:duty_id/documents/:id",
        DocumentController,
        :show

    post "/entities/:entity_slug/duties/:duty_id/documents",
         DocumentController,
         :create
  end

  scope "/", TugasWeb do
    pipe_through [:browser, TugasWeb.Plugs.AutoRouteByDevice]

    live_session :current_user,
      on_mount: [{TugasWeb.UserAuth, :mount_current_scope}, {TugasWeb.Locale, :default}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
      live "/invitations/:token", InvitationLive.Show, :show
      live "/m/invitations/:token", MobileLive.InvitationShow, :show
    end

    # Legacy /m/users/* bookmarks — AutoRouteByDevice redirects to /users/* before
    # PageController runs; routes exist only so the plug pipeline is entered.
    get "/m/users/register", PageController, :home
    get "/m/users/log-in/:token", PageController, :home
    get "/m/users/log-in", PageController, :home

    post "/invitations/:token/accept", InvitationController, :accept
    post "/m/invitations/:token/accept", InvitationController, :mobile_accept
    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
