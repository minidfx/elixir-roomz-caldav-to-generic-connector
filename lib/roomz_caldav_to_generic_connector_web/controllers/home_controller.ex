defmodule RoomzCaldavToGenericConnectorWeb.MainController do
  use RoomzCaldavToGenericConnectorWeb, :controller

  def index(conn, _params),
    do:
      conn
      |> put_resp_header("content-type", "text/html; charset=utf-8")
      |> send_file(
        200,
        Application.app_dir(
          :roomz_caldav_to_generic_connector,
          "priv/static/index.html"
        )
      )
end
