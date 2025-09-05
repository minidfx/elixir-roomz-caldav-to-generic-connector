defmodule RoomzCaldavToGenericConnectorWeb.ImageController do
  use RoomzCaldavToGenericConnectorWeb, :controller

  import Guards

  alias RoomzCaldavToGenericConnector.Servers

  action_fallback RoomzCaldavToGenericConnectorWeb.FallbackController

  def index(conn, %{"room_id" => room_id, "meeting_id" => meeting_id})
      when is_not_nil_or_empty_string(room_id) and
             is_not_nil_or_empty_string(meeting_id) do
    with {:ok, %Vix.Vips.Image{} = image} <- Servers.get_image(room_id, meeting_id),
         {:ok, binary} <-
           Image.write(image, :memory,
             suffix: ".png",
             quality: 10,
             strip_metadata: true,
             progressive: true
           ) do
      conn
      |> put_resp_content_type("image/png")
      |> send_resp(200, binary)
    end
  end

  def index(_conn, _params) do
    {:error, :not_found}
  end
end
