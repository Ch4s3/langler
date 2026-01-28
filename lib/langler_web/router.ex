defmodule LanglerWeb.Router do
  @moduledoc """
  Defines application routes and pipelines.
  """

  use LanglerWeb, :router

  import LanglerWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {LanglerWeb.Layouts, :root}
    plug :protect_from_forgery

    plug :put_secure_browser_headers, %{
      "content-security-policy" =>
        "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self' wss:; media-src 'self' blob:; object-src 'none'; frame-ancestors 'self'"
    }

    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", LanglerWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Other scopes may use custom stacks.
  # scope "/api", LanglerWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:langler, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: LanglerWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", LanglerWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{LanglerWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
      live "/users/settings/llm", UserLive.LlmSettings, :index
      live "/users/settings/tts", UserLive.TtsSettings, :index
      live "/users/settings/google-translate", UserLive.GoogleTranslateSettings, :index
      live "/users/invites", UserLive.Invites, :index
      live "/articles", ArticleLive.Index, :index
      live "/articles/recommendations", ArticleLive.Recommendations, :index
      live "/articles/:id", ArticleLive.Show, :show
      live "/articles/:id/listen", AudioLive.Player, :show
      live "/study", StudyLive.Index, :index
      live "/study/session", StudyLive.Session, :index

      # Admin routes
      live "/admin/source-sites", Admin.SourceSitesLive.Index, :index
      live "/admin/source-sites/new", Admin.SourceSitesLive.Form, :new
      live "/admin/source-sites/:id/edit", Admin.SourceSitesLive.Form, :edit
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", LanglerWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{LanglerWeb.UserAuth, :mount_current_scope}] do
      # Registration requires invite token - only accessible via invite link
      # In production, only allow registration with token (invite-only)
      # In dev/test, allow registration without token for testing
      if Application.compile_env(:langler, :env) != :prod do
        live "/users/register", UserLive.Registration, :new
      end
      live "/users/register/:token", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
