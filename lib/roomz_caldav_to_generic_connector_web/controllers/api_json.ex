defmodule RoomzCaldavToGenericConnectorWeb.ApiJSON do
  alias RoomzCaldavToGenericConnector.Event
  alias RoomzCaldavToGenericConnector.Room

  def rooms(%{rooms: []}), do: []

  def rooms(%{rooms: [%Room{} | _] = rooms}),
    do: Enum.map(rooms, fn %Room{} = room -> %{roomId: room.id, name: room.display_name} end)

  def meetings(%{events: []}), do: []

  def meetings(%{events: [%Event{} | _] = events}), do: Enum.map(events, &to_roomz_meeting/1)

  # Internal

  defp to_roomz_meeting(%Event{} = event) do
    %Event{
      meeting_id: id,
      subject: subject,
      organizer_id: organizer,
      start_date_utc: from,
      end_date_utc: to,
      creation_date_utc: modified,
      image_url: event_url
    } = event

    image_url = if(is_nil(event_url), do: nil, else: URI.to_string(event_url))

    %{
      meetingId: id,
      subject: subject,
      organizerId: organizer,
      startDateUTC: DateTimeHelper.to_string(from),
      endDateUTC: DateTimeHelper.to_string(to),
      creationDateUTC: DateTimeHelper.to_string(modified),
      isPrivate: false,
      isCancelled: false,
      imageUrl: image_url
    }
  end
end
