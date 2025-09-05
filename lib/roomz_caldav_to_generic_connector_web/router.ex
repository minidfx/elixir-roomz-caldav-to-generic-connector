defmodule RoomzCaldavToGenericConnectorWeb.Router do
  use RoomzCaldavToGenericConnectorWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug BasicAuth
    plug :accepts, ["json"]
  end

  scope "/", RoomzCaldavToGenericConnectorWeb do
    pipe_through :browser

    get "/", MainController, :index
  end

  scope "/", RoomzCaldavToGenericConnectorWeb do
    pipe_through :api

    get "/rooms", ApiController, :rooms
    get "/rooms/:room_id/meetings", ApiController, :meetings

    post "/rooms/:room_id/meetings", ApiController, :new_meeting
    put "/rooms/:room_id/meetings/:meeting_id", ApiController, :update_meeting
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:roomz_caldav_to_generic_connector, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      live_dashboard "/dashboard", metrics: RoomzCaldavToGenericConnectorWeb.Telemetry
    end
  end
end
