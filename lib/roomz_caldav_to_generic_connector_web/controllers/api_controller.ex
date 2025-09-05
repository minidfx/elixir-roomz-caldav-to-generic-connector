defmodule RoomzCaldavToGenericConnectorWeb.ApiController do
  use RoomzCaldavToGenericConnectorWeb, :controller

  import Guards

  action_fallback RoomzCaldavToGenericConnectorWeb.FallbackController

  alias RoomzCaldavToGenericConnector.Servers

  def rooms(conn, _params) do
    with {:ok, rooms} <- Servers.get_rooms() do
      render(conn, :rooms, rooms: rooms)
    end
  end

  def meetings(conn, %{"room_id" => room_id, "from" => raw_from, "to" => raw_to})
      when is_not_nil_or_empty_string(room_id) do
    with {:ok, from} <- DateTimeHelper.parse(raw_from),
         {:ok, to} <- DateTimeHelper.parse(raw_to),
         {:ok, interval} <- DateTimeHelper.to_interval(from, to),
         {:ok, events} <- Servers.get_events(room_id, interval) do
      render(conn, :meetings, events: events)
    end
  end

  def meetings(conn, _) do
    conn
    |> put_status(400)
    |> put_view(json: RoomzCaldavToGenericConnectorWeb.ErrorJSON)
    |> render(:"400")
  end

  def new_meeting(conn, %{"room_id" => room_id} = params)
      when is_not_nil_or_empty_string(room_id) do
    atom_key_map =
      params
      |> Stream.map(fn {k, v} -> {String.to_atom(k), v} end)
      |> Map.new()

    with {:ok, new_meeting} <- NewMeeting.builder(Map.put_new(atom_key_map, :id, UUID.uuid4())),
         :ok <- Servers.new_event(room_id, new_meeting) do
      send_resp(conn, 201, "")
    end
  end

  def new_meeting(conn, _) do
    conn
    |> put_status(400)
    |> put_view(json: RoomzCaldavToGenericConnectorWeb.ErrorJSON)
    |> render(:"400")
  end

  def update_meeting(conn, %{"room_id" => room_id, "meeting_id" => meeting_id} = params)
      when is_not_nil_or_empty_string(room_id) and
             is_not_nil_or_empty_string(meeting_id) do
    atom_key_map =
      params
      |> Stream.map(fn {k, v} -> {String.to_atom(k), v} end)
      |> Map.new()

    with {:ok, update_meeting} <- UpdateMeeting.builder(Map.put(atom_key_map, :id, meeting_id)),
         :ok <- Servers.update_event(room_id, update_meeting) do
      send_resp(conn, 204, "")
    end
  end

  def update_meeting(conn, _) do
    conn
    |> put_status(400)
    |> put_view(json: RoomzCaldavToGenericConnectorWeb.ErrorJSON)
    |> render(:"400")
  end
end
