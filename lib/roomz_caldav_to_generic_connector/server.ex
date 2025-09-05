defmodule RoomzCaldavToGenericConnector.Server do
  use GenServer

  import Guards

  require Logger

  alias RoomzCaldavToGenericConnector.CalendarReader
  alias RoomzCaldavToGenericConnector.CalendearReaderResult
  alias RoomzCaldavToGenericConnector.Room
  alias RoomzCaldavToGenericConnector.ServerState

  @allowed_image_extensions MapSet.new([".png", ".jpg", ".jpeg", ".bmp"])
  @allowed_mime_types MapSet.new(["image/jpg", "image/jpeg", "image/png", "image/bmp"])

  # Client

  def start_link(%ServerState{} = init_args) do
    server_name = server_name(init_args)
    Logger.debug("Starting the server #{server_name} ...")

    GenServer.start_link(__MODULE__, init_args, name: {:global, server_name})
  end

  def server_name(%ServerState{id: x}), do: "caldav_#{x}"

  def create_user_url(%URI{} = base_server_url, username)
      when is_bitstring(username) do
    uri = URI.append_path(base_server_url, "/calendars/#{URI.encode(username)}")
    {:ok, uri}
  end

  def to_room(%URI{} = base_server_url, %CalendearReaderResult{} = result) do
    %CalendearReaderResult{urn: urn, display_name: dp} = result

    %Room{
      id: extract_id!(urn),
      urn: create_calendar_urn(base_server_url, urn),
      display_name: dp
    }
  end

  # Server (callbacks)

  @impl true
  def init(%ServerState{} = init_args) do
    Process.send_after(self(), :refresh_rooms, 1)

    {:ok, init_args}
  end

  @impl true
  def handle_info(:refresh_rooms, state) do
    %ServerState{id: server_id, client: client, uri: base_server_url} = state

    Logger.debug("Loading the rooms available on the server #{server_id} ...")

    with tesla_client <- CalDAVClient.Tesla.make_tesla_client(client),
         {:ok, env} <-
           Tesla.request(tesla_client,
             method: :propfind,
             url: URI.to_string(base_server_url),
             headers: [{"Depth", 1}]
           ),
         %Tesla.Env{status: 207, body: content} <- env,
         {:ok, xml} <- Saxy.SimpleForm.parse_string(content) do
      rooms =
        xml
        |> CalendarReader.read()
        |> Stream.map(&to_room(base_server_url, &1))
        |> Stream.map(fn %Room{id: id} = room -> {id, room} end)
        |> Map.new()

      state = %ServerState{state | rooms: rooms}

      Logger.debug("Sending the new rooms to the dispatcher from the server #{server_id} ...")

      GenServer.cast(RoomzCaldavToGenericConnector.Servers, {:update_mappings, state})

      Logger.debug(
        "Scheduling the update of the mappings between rooms and servers for the server #{server_id} ..."
      )

      Process.send_after(
        self(),
        :refresh_rooms,
        Timex.Duration.from_minutes(10) |> Timex.Duration.to_milliseconds(truncate: true)
      )

      {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:get_events, caller, room_id, from, to}, state) do
    Logger.debug("""
    Received the request #{inspect(:get_events)}.
      Caller: #{inspect(caller)}
      Server: #{inspect(self())}
    """)

    with %ServerState{client: client, rooms: rooms, username: u} <- state,
         {:ok, room} <- Map.fetch(rooms, room_id),
         %Room{id: id} <- room,
         calendar_url <- CalDAVClient.URL.Builder.build_calendar_url(u, id),
         {:ok, ical_events} <- CalDAVClient.Event.get_events(client, calendar_url, from, to),
         interval <-
           Timex.Interval.new(from: from, until: to, left_open: false, right_open: false),
         events <- translate_events(interval, ical_events),
         events <- skip_invalid_images(events) do
      GenServer.reply(caller, {:ok, Enum.to_list(events)})

      Logger.debug("""
      Replied to the caller #{inspect(:get_events)}.
        Caller: #{inspect(caller)}
        Server: #{inspect(self())}
      """)

      {:noreply, state}
    else
      {:error, reason} ->
        GenServer.reply(caller, {:error, reason})
        {:noreply, state}

      x ->
        GenServer.reply(caller, {:error, inspect(x)})
        {:reply, state}
    end
  end

  @impl true
  def handle_cast({:new_event, caller, room_id, new_event}, state) do
    Logger.debug("""
    Received the request #{inspect(:new_event)}.
      Caller: #{inspect(caller)}
      Server: #{inspect(self())}
    """)

    %NewMeeting{id: event_id, startDateUTC: context_time} = new_event

    with %ServerState{client: client, rooms: rooms, username: u} <- state,
         {:ok, room} <- Map.fetch(rooms, room_id),
         :not_found <- get_context_event(state, room, context_time),
         %Room{id: id} <- room,
         calendar_url <- CalDAVClient.URL.Builder.build_calendar_url(u, id),
         event_url <- CalDAVClient.URL.Builder.build_event_url(calendar_url, event_id),
         ical_new_event <- create_icalendar_event(new_event),
         {:ok, _etag} <- CalDAVClient.Event.create(client, event_url, ical_new_event) do
      GenServer.reply(caller, :ok)
      {:noreply, state}
    else
      :found ->
        GenServer.reply(caller, {:error, "Conflicting event!"})
        {:noreply, state}

      {:error, reason} ->
        GenServer.reply(caller, {:error, reason})
        {:noreply, state}

      x ->
        GenServer.reply(caller, {:error, inspect(x)})
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:update_event, caller, room_id, update_event}, state) do
    Logger.debug("""
    Received the request #{inspect(:update_event)}.
      Caller: #{inspect(caller)}
      Server: #{inspect(self())}
    """)

    %UpdateMeeting{id: update_event_id} = update_event

    with %ServerState{client: client, rooms: rooms, username: u} <- state,
         {:ok, room} <- Map.fetch(rooms, room_id),
         %Room{id: id} <- room,
         calendar_url <- CalDAVClient.URL.Builder.build_calendar_url(u, id),
         {:ok, raw_file} <- CalDAVClient.Event.find_by_uid(client, calendar_url, update_event_id),
         %CalDAVClient.Event{url: url} <- raw_file,
         file_name <- Path.basename(url),
         event_url <- CalDAVClient.URL.Builder.build_event_url(calendar_url, file_name),
         {:ok, raw_event, etag} <- CalDAVClient.Event.get(client, event_url),
         [%ICalendar.Event{} = event] <- ICalendar.from_ics(raw_event),
         ical_update_event <- create_icalendar_event(event, update_event),
         {:ok, _etag} <-
           CalDAVClient.Event.update(
             client,
             event_url,
             ical_update_event,
             etag: etag
           ) do
      GenServer.reply(caller, :ok)
      {:noreply, state}
    else
      :not_found ->
        GenServer.reply(caller, {:error, "The given event #{update_event_id} was not found."})
        {:noreply, state}

      {:error, reason} ->
        GenServer.reply(caller, {:error, reason})
        {:noreply, state}

      x ->
        GenServer.reply(caller, {:error, inspect(x)})
        {:noreply, state}
    end
  end

  @impl true
  def handle_call(:get_rooms, _from, state) do
    %ServerState{rooms: rooms} = state
    {:reply, {:ok, rooms}, state}
  end

  # Internals

  defp create_calendar_urn(%URI{path: path}, urn) do
    urn
    |> String.trim_leading(path)
    |> String.trim("/")
  end

  defp extract_id!(urn) when is_bitstring(urn) do
    urn
    |> String.split("/", trim: true)
    |> List.last() || raise "Was not able to extract the calendar id."
  end

  defp create_icalendar_event(%NewMeeting{} = new_event) do
    %NewMeeting{
      subject: subject,
      id: event_id,
      organizer_id: organizer_id,
      startDateUTC: startDateUTC,
      endDateUTC: endDateUTC
    } = new_event

    event = %ICalendar.Event{
      uid: event_id,
      summary: subject,
      dtstart: Timex.format!(startDateUTC, "{ISO:Basic:Z}"),
      dtend: Timex.format!(endDateUTC, "{ISO:Basic:Z}"),
      organizer: organizer_id
    }

    ics = ICalendar.to_ics(event)

    # INFO: https://datatracker.ietf.org/doc/html/rfc4791#section-5.3.2
    """
    BEGIN:VCALENDAR
    VERSION:2.0
    PRODID:-//CalDAVtoROOMZ//CalDAV Client//EN
    #{ics}
    END:VCALENDAR
    """
  end

  defp create_icalendar_event(
         %ICalendar.Event{} = original_event,
         %UpdateMeeting{} = update_event
       )
       when original_event.uid == update_event.id do
    %UpdateMeeting{
      startDateUTC: start_date_utc,
      endDateUTC: end_date_utc
    } = update_event

    %ICalendar.Event{
      uid: event_id,
      summary: subject,
      organizer: organizer_id
    } = original_event

    event = %ICalendar.Event{
      uid: event_id,
      summary: subject,
      dtstart: Timex.format!(start_date_utc, "{ISO:Basic:Z}"),
      dtend: Timex.format!(end_date_utc, "{ISO:Basic:Z}"),
      organizer: organizer_id
    }

    ics = ICalendar.to_ics(event)

    # INFO: https://datatracker.ietf.org/doc/html/rfc4791#section-5.3.2
    """
    BEGIN:VCALENDAR
    VERSION:2.0
    PRODID:-//CalDAVtoROOMZ//CalDAV Client//EN
    #{ics}
    END:VCALENDAR
    """
  end

  defp get_context_event(%ServerState{} = server, %Room{} = room, %DateTime{} = context_time)
       when is_utc(context_time) do
    with %ServerState{client: client, username: u} <- server,
         %Room{id: id} <- room,
         calendar_url = CalDAVClient.URL.Builder.build_calendar_url(u, id),
         {:ok, events} <-
           CalDAVClient.Event.get_events(
             client,
             calendar_url,
             context_time,
             Timex.shift(context_time, minutes: 1)
           ) do
      # HACK: If we have multiple events, return the first one. This solution to mitigate the issue and avoid to crash.
      if(Enum.any?(events), do: {:found, Enum.take(events, 1)}, else: :not_found)
    else
      {:error, reason} -> {:error, reason}
      x -> {:error, inspect(x)}
    end
  end

  defp translate_events(_interval, []), do: []

  defp translate_events(%Timex.Interval{} = interval, ical_events)
       when is_list(ical_events) do
    ical_events
    |> Stream.map(&extract_ical/1)
    |> Stream.flat_map(&ICalendar.from_ics/1)
    |> Stream.map(&translate_event(interval, &1))
    |> Stream.concat()
  end

  defp translate_event(
         %Timex.Interval{} = interval,
         %ICalendar.Event{rrule: %{}} = ical_event
       ) do
    %ICalendar.Event{
      dtstart: event_from,
      dtend: event_to,
      rrule: recurrence
    } = ical_event

    event_from_utc = DatetimeValidator.to_utc(event_from)
    event_to_utc = DatetimeValidator.to_utc(event_to)
    event_interval = Timex.Interval.new(from: event_from_utc, until: event_to_utc)

    Timex.Interval.new(
      from: event_from,
      until: interval.until,
      step: recurrence_to_steps(recurrence)
    )
    |> Stream.map(&to_event_interval(&1, event_interval))
    |> Stream.filter(fn x -> Timex.Interval.contains?(interval, x) end)
    |> Stream.map(&to_event(&1, ical_event))
  end

  defp translate_event(_interval, %ICalendar.Event{rrule: nil} = ical_event) do
    %ICalendar.Event{
      dtstart: from,
      dtend: to
    } = ical_event

    event_from_utc = DatetimeValidator.to_utc(from)
    event_to_utc = DatetimeValidator.to_utc(to)
    event_interval = Timex.Interval.new(from: event_from_utc, until: event_to_utc)

    [to_event(event_interval, ical_event)]
  end

  defp to_event_interval(%NaiveDateTime{} = step, %Timex.Interval{} = event_interval) do
    %Timex.Interval{from: from} = event_interval
    %NaiveDateTime{hour: h1, minute: m1, second: s1} = from
    %Date{day: d, month: m, year: y} = Timex.to_date(step)

    event_duration = Timex.Interval.duration(event_interval, :duration)
    local_from = Timex.to_datetime({{y, m, d}, {h1, m1, s1}})
    local_to = Timex.shift(local_from, duration: event_duration)

    Timex.Interval.new(from: local_from, until: local_to)
  end

  defp to_event(
         %Timex.Interval{} = event_interval,
         %ICalendar.Event{} = original_event
       ) do
    %Timex.Interval{from: local_from, until: local_to} = event_interval
    %ICalendar.Event{url: event_url} = original_event

    # HACK: Because the property is required, use the start date of the event if it is missing.
    image_url = if(is_nil(event_url), do: nil, else: URI.parse(event_url))

    modified =
      if(is_nil(original_event.modified),
        do: local_from,
        else: DatetimeValidator.to_utc(original_event.modified)
      )

    %Event{
      subject: original_event.summary,
      start_date_utc: DatetimeValidator.to_utc(local_from),
      end_date_utc: DatetimeValidator.to_utc(local_to),
      meeting_id: original_event.uid,
      organizer_id: original_event.organizer,
      creation_date_utc: modified,
      image_url: image_url,
      is_private: false,
      is_cancelled: false
    }
  end

  defp skip_invalid_images(stream_of_events),
    do:
      stream_of_events
      |> Task.async_stream(&skip_invalid_image/1)
      |> Stream.filter(&match?({:ok, _}, &1))
      |> Stream.map(fn {:ok, x} -> x end)

  defp skip_invalid_image(%Event{image_url: nil} = event), do: event

  defp skip_invalid_image(%Event{} = event) do
    with {:error, reason1} <- keep_image_with_allowed_extensions(event),
         {:error, reason2} <- keep_image_with_allowed_mime_types(event) do
      Logger.info("Invalid image: #{reason1}, #{reason2}")
      %Event{event | image_url: nil}
    else
      {:ok, %Event{} = event} -> event
      unsupported -> raise "Unsupported error: #{inspect(unsupported)}"
    end
  end

  defp keep_image_with_allowed_extensions(%Event{image_url: uri} = event) do
    with %URI{path: path} when is_not_nil_or_empty_string(path) <- uri,
         extension when is_not_nil_or_empty_string(extension) <- Path.extname(path) do
      if(MapSet.member?(@allowed_image_extensions, extension),
        do: {:ok, event},
        else: {:error, "Invalid extension: #{extension}"}
      )
    else
      "" -> {:error, "Didn't find the extension of #{URI.to_string(uri)}"}
      reason -> {:error, reason}
    end
  end

  defp keep_image_with_allowed_mime_types(%Event{image_url: uri} = event) do
    with {:ok, resp} <- Req.head(uri),
         %Req.Response{status: status} when status in [200, 204] <- resp,
         %Req.Response{headers: headers} <- resp,
         {:ok, content_type} <- Map.fetch(headers, "content-type") do
      if(MapSet.member?(@allowed_mime_types, content_type),
        do: {:ok, event},
        else: {:error, "Invalid mime type: #{content_type}"}
      )
    else
      %Req.Response{status: status} -> {:error, "Invalid status returned: #{status}"}
      :error -> {:error, "Didn't find the header content-type"}
      reason -> {:error, reason}
    end
  end

  defp recurrence_to_steps(%{freq: "DAILY"}), do: [days: 1]
  defp recurrence_to_steps(%{freq: "WEEKLY"}), do: [weeks: 1]
  defp recurrence_to_steps(%{freq: "YEARLY"}), do: [years: 1]

  defp extract_ical(%CalDAVClient.Event{icalendar: ics}), do: ics
end
