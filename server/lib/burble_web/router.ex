# SPDX-License-Identifier: PMPL-1.0-or-later
#
# BurbleWeb.Router — HTTP routing for the Burble API.

defmodule BurbleWeb.Router do
  use Phoenix.Router, helpers: false

  import Plug.Conn
  import Phoenix.Controller
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BurbleWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :authenticated_api do
    plug :accepts, ["json"]
    plug Burble.Auth.GuardianPipeline
  end

  # Public API routes (no auth required).
  scope "/api/v1", BurbleWeb.API do
    pipe_through :api

    # Auth (public — issues tokens)
    post "/auth/register", AuthController, :register
    post "/auth/login", AuthController, :login
    post "/auth/guest", AuthController, :guest
    post "/auth/magic-link", AuthController, :magic_link
    post "/auth/refresh", AuthController, :refresh

    # Invite acceptance (public — uses invite token, not auth token)
    post "/invites/:token/accept", InviteController, :accept

    # Diagnostics (public — self-test before joining voice)
    get "/diagnostics/self-test", DiagnosticsController, :self_test
    get "/diagnostics/self-test/:mode", DiagnosticsController, :self_test
  end

  # Authenticated API routes (require valid JWT).
  scope "/api/v1", BurbleWeb.API do
    pipe_through :authenticated_api

    delete "/auth/logout", AuthController, :logout

    # Servers
    get "/servers", ServerController, :index
    post "/servers", ServerController, :create
    get "/servers/:id", ServerController, :show

    # Rooms
    get "/servers/:server_id/rooms", RoomController, :index
    post "/servers/:server_id/rooms", RoomController, :create
    get "/rooms/:id", RoomController, :show
    get "/rooms/:id/participants", RoomController, :participants

    # Invites (creation requires auth)
    post "/servers/:server_id/invites", InviteController, :create
  end

  # LiveDashboard for operators (dev + prod with auth)
  if Application.compile_env(:burble, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser
      live_dashboard "/dashboard", metrics: Burble.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  # Serve the MVP web client at root
  scope "/", BurbleWeb do
    pipe_through :browser
    get "/", PageController, :index
  end

  @doc false
  def static_paths, do: ~w(assets fonts images favicon.ico robots.txt index.html)
end

defmodule BurbleWeb do
  @moduledoc false

  def static_paths, do: BurbleWeb.Router.static_paths()
end
