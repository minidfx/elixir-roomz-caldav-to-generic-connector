defmodule RoomzCaldavToGenericConnector.Server do
  use GenServer
  use RoomzCaldavToGenericConnectorWeb, :verified_routes

  import Guards

  require Logger

  alias RoomzCaldavToGenericConnector.CalendarReader
  alias RoomzCaldavToGenericConnector.CalendearReaderResult
  alias RoomzCaldavToGenericConnector.DownloadImagesRequest
  alias RoomzCaldavToGenericConnector.Event
  alias RoomzCaldavToGenericConnector.EventBag
  alias RoomzCaldavToGenericConnector.EventCached
  alias RoomzCaldavToGenericConnector.EventsBag
  alias RoomzCaldavToGenericConnector.ImageServer
  alias RoomzCaldavToGenericConnector.Room
  alias RoomzCaldavToGenericConnector.ServerState
  alias Vix.Vips.Image

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
  def init(%ServerState{} = state) do
    {:ok, state, {:continue, :refresh_rooms}}
  end

  @impl true
  def handle_continue(:refresh_rooms, state) do
    refresh_rooms(state)
  end

  @impl true
  def handle_continue({:download_images, room_id}, state)
      when is_not_nil_or_empty_string(room_id) do
    with true <-
           Application.fetch_env!(
             :roomz_caldav_to_generic_connector,
             :prefetch_images
           ),
         %ServerState{rooms: rooms} <- state,
         {:ok, room} <- Map.fetch(rooms, room_id),
         %Room{events_cached: events_cached} <- room do
      images_to_pull =
        events_cached
        |> Map.values()
        |> Stream.filter(fn
          %EventCached{image: _, uri: :none} -> false
          %EventCached{image: :error, uri: _} -> false
          %EventCached{image: {:ok, _}, uri: _} -> false
          %EventCached{image: :none, uri: {:ok, _}} -> true
        end)
        |> Enum.to_list()

      # INFO: Fire a message to try to pull the images from the events
      ImageServer.download_images(%DownloadImagesRequest{
        server: self(),
        events: images_to_pull
      })

      {:noreply, state}
    else
      false ->
        Logger.notice("The images were not pre-downloaded because the feature has been disabled.")
        {:noreply, state}

      x ->
        Logger.warning("Unsupported result while preparing the image download: #{inspect(x)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:refresh_rooms, state) do
    refresh_rooms(state)
  end

  @impl true
  def handle_cast({:get_image, caller, room_id, meeting_id}, state) do
    with %ServerState{rooms: rooms} <- state,
         %Room{events_cached: events_cached} <- Map.get(rooms, room_id, :room_not_found),
         %EventCached{image: {:ok, %Image{} = image}} <-
           Map.get(events_cached, meeting_id, :event_not_found) do
      GenServer.reply(caller, {:ok, image})
    else
      :room_not_found ->
        GenServer.reply(caller, {:error, "The given room_id was not found: #{room_id}"})

      :event_not_found ->
        GenServer.reply(caller, {:error, "The given meeting_id was not found: #{meeting_id}"})

      %EventCached{image: _} ->
        GenServer.reply(
          caller,
          {:error, "The image for the given meeting_id was not found: #{meeting_id}"}
        )

      x ->
        GenServer.reply(caller, {:error, "Unhandled error: #{inspect(x)}"})
    end

    {:noreply, state}
  end

  @impl true
  def handle_cast({:update_images, []}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_cast({:update_images, event_caches}, state) when is_list(event_caches) do
    Logger.debug("Received images downloaded, updating the caches ...")

    state =
      event_caches
      |> Enum.group_by(fn %EventCached{room_id: x} -> x end)
      |> Enum.reduce(state, &update_image_caches/2)

    {:noreply, state}
  end

  @impl true
  def handle_cast({:get_events, caller, room_id, from, to}, state) do
    context_time = Timex.now()

    Logger.debug("""
    Received the request #{inspect(:get_events)}.
      Caller: #{inspect(caller)}
      Server: #{inspect(self())}
    """)

    %ServerState{client: client, rooms: rooms, username: u} = state

    with %Room{} = room <- Map.get(rooms, room_id, :room_not_found),
         %Room{id: room_id, events_cached: events_cached} <- room,
         calendar_url <- CalDAVClient.URL.Builder.build_calendar_url(u, room_id),
         {:ok, caldav_events} <-
           CalDAVClient.Event.get_events(
             client,
             calendar_url,
             from,
             to,
             expand: true
           ),
         interval <-
           Timex.Interval.new(
             from: from,
             until: to,
             left_open: true,
             right_open: false
           ),
         events_cached_by_id <- cleanup_events_cached(context_time, events_cached),
         bag <- %EventsBag{
           room_id: room_id,
           context_time: context_time,
           interval: interval,
           caldav_events: caldav_events,
           events_cached: events_cached_by_id
         },
         bag <- create_events(bag),
         %EventsBag{events: event_bags} <- bag do
      events =
        event_bags
        |> Stream.map(fn %EventBag{events: x} -> x end)
        |> Stream.concat()
        |> Enum.sort_by(fn %Event{start_date_utc: x} -> Timex.to_unix(x) end, :asc)

      GenServer.reply(caller, {:ok, events})

      Logger.debug("""
      Replied to the caller #{inspect(:get_events)}.
        Caller: #{inspect(caller)}
        Server: #{inspect(self())}
      """)

      new_events_cached =
        event_bags
        |> Stream.filter(fn %EventBag{event_cached: x} -> !is_nil(x) end)
        |> Stream.map(fn %EventBag{event_cached: x} -> x end)
        |> Stream.filter(fn %EventCached{interval: %Timex.Interval{until: to}} ->
          Timex.before?(context_time, to)
        end)
        |> Enum.to_list()

      new_events_cached_by_id =
        new_events_cached
        |> Stream.map(fn %EventCached{id: id} = x -> {id, x} end)
        |> Map.new()

      {
        :noreply,
        %ServerState{
          state
          | rooms:
              Map.put(
                rooms,
                room_id,
                %Room{room | events_cached: new_events_cached_by_id}
              )
        },
        {:continue, {:download_images, room_id}}
      }
    else
      {:error, reason} ->
        GenServer.reply(caller, {:error, reason})
        {:noreply, state}

      :room_not_found ->
        GenServer.reply(caller, {:error, "The room was not found."})
        {:noreply, state}

      x ->
        GenServer.reply(caller, {:error, "Unsupported error: #{inspect(x)}"})
        {:noreply, state}
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
        GenServer.reply(caller, {:conflict, "Another meeting already exist at the same interval"})
        {:noreply, state}

      {:error, reason} ->
        GenServer.reply(caller, {:error, reason})
        {:noreply, state}

      x ->
        GenServer.reply(caller, {:error, "Unsupported error: #{inspect(x)}"})
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
        GenServer.reply(caller, {:error, "Unsupported error: #{inspect(x)}"})
        {:noreply, state}
    end
  end

  @impl true
  def handle_call(:get_rooms, _from, state) do
    %ServerState{rooms: rooms} = state
    {:reply, {:ok, rooms}, state}
  end

  # Internals

  defp update_image_caches({room_id, caches}, %ServerState{rooms: rooms} = state)
       when is_list(caches) and
              is_not_nil_or_empty_string(room_id) do
    with {:ok, room} <- Map.fetch(rooms, room_id),
         %Room{events_cached: events_cached} <- room do
      caches
      |> Enum.reduce(events_cached, &update_image_cache/2)
      |> then(fn x -> %Room{room | events_cached: x} end)
      |> then(fn x -> %ServerState{state | rooms: Map.put(rooms, room_id, x)} end)
    else
      :error -> state
    end
  end

  defp update_image_cache(
         %EventCached{id: updated_cache_id, image: image_result},
         %{} = event_caches
       ) do
    with {:ok, existing_event_cached} <- Map.fetch(event_caches, updated_cache_id),
         %EventCached{id: existing_cache_id} <- existing_event_cached do
      Map.put(
        event_caches,
        existing_cache_id,
        %EventCached{existing_event_cached | image: image_result}
      )
    else
      _ -> event_caches
    end
  end

  defp cleanup_events_cached(%DateTime{} = context_time, %{} = events_cached)
       when is_utc(context_time) do
    events_cached
    |> Map.values()
    |> Stream.filter(fn %EventCached{interval: %Timex.Interval{until: to}} ->
      Timex.before?(context_time, to)
    end)
    |> Stream.map(fn %EventCached{id: x} = event -> {x, event} end)
    |> Map.new()
  end

  defp refresh_rooms(%ServerState{} = state) do
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
      rooms_by_id =
        xml
        |> CalendarReader.read()
        |> Stream.map(&to_room(base_server_url, &1))
        |> Stream.map(fn %Room{id: id} = room -> {id, room} end)
        |> Map.new()

      state = %ServerState{state | rooms: rooms_by_id}

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
    else
      error ->
        Logger.error(
          "Error while fetching the rooms from the caldav server #{base_server_url}: #{inspect(error)}"
        )

        Logger.debug("Retry to fetch the rooms in 2 minutes.")

        Process.send_after(
          self(),
          :refresh_rooms,
          Timex.Duration.from_minutes(2) |> Timex.Duration.to_milliseconds(truncate: true)
        )

        {:noreply, state}
    end
  end

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

  defp create_events(%EventsBag{caldav_events: []} = bag), do: bag

  defp create_events(%EventsBag{} = bag) do
    %EventsBag{
      caldav_events: caldav_events,
      events_cached: events_cached,
      interval: interval,
      room_id: room_id
    } = bag

    events_joined =
      caldav_events
      |> Stream.flat_map(&flatten_ical_events/1)
      |> Stream.map(&join_events(&1, events_cached, room_id))
      |> Stream.map(&translate_event(&1, interval))
      |> Enum.to_list()

    %EventsBag{bag | events: events_joined}
  end

  defp translate_event(
         %EventBag{ical_event: %ICalendar.Event{rrule: %{}} = ical_event} = bag,
         %Timex.Interval{} = interval
       ) do
    %ICalendar.Event{
      dtstart: event_from,
      dtend: event_to,
      rrule: recurrence
    } = ical_event

    %EventBag{event_cached: %EventCached{} = event_cached} = bag

    event_from_utc = DatetimeValidator.to_utc(event_from)
    event_to_utc = DatetimeValidator.to_utc(event_to)
    event_interval = Timex.Interval.new(from: event_from_utc, until: event_to_utc)

    new_events =
      Timex.Interval.new(
        from: event_from,
        until: interval.until,
        step: recurrence_to_steps(recurrence)
      )
      |> Stream.map(&to_event_interval(&1, event_interval))
      |> Stream.filter(&Timex.Interval.contains?(interval, &1))
      |> Stream.map(&to_event(&1, ical_event, event_cached))
      |> Enum.to_list()

    %EventBag{bag | events: new_events}
  end

  defp translate_event(
         %EventBag{ical_event: %ICalendar.Event{rrule: nil} = ical_event} = bag,
         _interval
       ) do
    %ICalendar.Event{
      dtstart: from,
      dtend: to
    } = ical_event

    %EventBag{event_cached: %EventCached{} = event_cached} = bag

    event_from_utc = DatetimeValidator.to_utc(from)
    event_to_utc = DatetimeValidator.to_utc(to)
    event_interval = Timex.Interval.new(from: event_from_utc, until: event_to_utc)

    %EventBag{bag | events: [to_event(event_interval, ical_event, event_cached)]}
  end

  defp flatten_ical_events(%CalDAVClient.Event{} = caldav_event) do
    with %CalDAVClient.Event{icalendar: raw_ical} <- caldav_event,
         ical_events <- ICalendar.from_ics(raw_ical) do
      Stream.map(ical_events, fn ical_event -> {caldav_event, ical_event} end)
    end
  end

  defp join_events(
         {
           %CalDAVClient.Event{} = caldav_event,
           %ICalendar.Event{} = ical_event
         },
         %{} = events_cached_by_id,
         room_id
       ) do
    with %CalDAVClient.Event{etag: etag} <- caldav_event,
         %ICalendar.Event{uid: id} <- ical_event do
      # Try to find out the event cached
      with {:ok, event_cached} <- Map.fetch(events_cached_by_id, id),
           %EventCached{etag: event_cached_etag} <- event_cached do
        # Is it the same event?
        if(String.equivalent?(event_cached_etag, etag),
          do: %EventBag{
            ical_event: ical_event,
            caldav_event: caldav_event,
            event_cached: event_cached
          },
          else: %EventBag{
            ical_event: ical_event,
            caldav_event: caldav_event,
            event_cached: %EventCached{event_cached | etag: etag, image: :none}
          }
        )
      else
        :error ->
          %ICalendar.Event{dtstart: start_date, dtend: end_date, url: raw_uri} = ical_event

          %EventBag{
            ical_event: ical_event,
            caldav_event: caldav_event,
            event_cached: %EventCached{
              id: id,
              room_id: room_id,
              etag: etag,
              image: :none,
              uri: safe_parse_uri(raw_uri),
              interval:
                Timex.Interval.new(
                  from: DatetimeValidator.to_utc(start_date),
                  until: DatetimeValidator.to_utc(end_date),
                  left_open: true,
                  right_open: false
                )
            }
          }
      end
    end
  end

  #
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
         %ICalendar.Event{} = original_event,
         %EventCached{} = event_cached
       ) do
    %Timex.Interval{from: local_from, until: local_to} = event_interval
    %EventCached{id: event_id, room_id: room_id} = event_cached

    # HACK: Because the property is required, use the start date of the event if it is missing.
    modified =
      if(is_nil(original_event.modified),
        do: local_from,
        else: DatetimeValidator.to_utc(original_event.modified)
      )

    uri =
      case event_cached do
        %EventCached{image: {:ok, %Image{}}} ->
          URI.new!(
            static_url(
              RoomzCaldavToGenericConnectorWeb.Endpoint,
              ~p"/rooms/#{room_id}/images/#{event_id}"
            )
          )

        _ ->
          nil
      end

    %Event{
      subject: original_event.summary,
      start_date_utc: DatetimeValidator.to_utc(local_from),
      end_date_utc: DatetimeValidator.to_utc(local_to),
      meeting_id: original_event.uid,
      organizer_id: original_event.organizer,
      creation_date_utc: DatetimeValidator.to_utc(modified),
      is_private: false,
      is_cancelled: false,
      image_url: uri
    }
  end

  defp safe_parse_uri(raw_uri) when is_not_nil_or_empty_string(raw_uri) do
    case URI.new(raw_uri) do
      {:ok, uri} -> {:ok, uri}
      {:error, _} -> :none
    end
  end

  defp safe_parse_uri(_raw_uri), do: :none

  defp recurrence_to_steps(%{freq: "DAILY"}), do: [days: 1]
  defp recurrence_to_steps(%{freq: "WEEKLY"}), do: [weeks: 1]
  defp recurrence_to_steps(%{freq: "YEARLY"}), do: [years: 1]
end
