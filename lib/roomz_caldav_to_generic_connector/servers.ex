defmodule RoomzCaldavToGenericConnector.Servers do
  @moduledoc """
  This server is responsible to dispatch the request to the right server dedicated to the CalDAV Server.
  """

  use GenServer

  import Guards

  require Logger

  alias RoomzCaldavToGenericConnector.Room
  alias RoomzCaldavToGenericConnector.Server
  alias RoomzCaldavToGenericConnector.ServersState
  alias RoomzCaldavToGenericConnector.ServerState
  alias Vix.Vips.Image

  # Client

  def start_link(%ServersState{} = init_args) do
    Logger.debug("Starting the servers client ...")
    GenServer.start_link(__MODULE__, init_args, name: __MODULE__)
  end

  @doc """
  Try to retrieve the image bound the given meeting_id.
  """
  @spec get_image(String.t(), String.t()) :: {:ok, %Image{}} | :error
  def get_image(room_id, meeting_id)
      when is_not_nil_or_empty_string(room_id) and
             is_not_nil_or_empty_string(meeting_id) do
    try do
      GenServer.call(__MODULE__, {:get_image, room_id, meeting_id})
    catch
      :exit, {:timeout, _} -> {:error, :timeout}
    end
  end

  @doc """
  Try to retrieve the rooms available on the CalDAV servers. Each calendars found is considered as a room.
  """
  def get_rooms() do
    try do
      case GenServer.call(__MODULE__, :get_rooms) do
        {:ok, rooms} -> {:ok, rooms}
        {:error, reason} -> {:error, reason}
      end
    catch
      :exit, {:timeout, _} -> {:error, :timeout}
    end
  end

  @doc """
  Try to read the events from the given room_id.
  """
  def get_events(room_id, %Timex.Interval{} = interval)
      when is_not_nil_or_empty_string(room_id) do
    try do
      with {:ok, events} <-
             GenServer.call(
               __MODULE__,
               {:get_events, room_id, interval},
               Application.fetch_env!(:roomz_caldav_to_generic_connector, :caldav_server_timeout)
             ) do
        {:ok, events}
      else
        {:error, reason} -> {:error, reason}
        :error -> {:error, "Cannot dispatch the request with the given room #{room_id}."}
        x -> raise "Unknown error: #{inspect(x)}"
      end
    catch
      :exit, {:timeout, _} -> {:error, :timeout}
    end
  end

  @doc """
  Try to create a new event
  """
  def new_event(room_id, %NewMeeting{} = new_event)
      when is_not_nil_or_empty_string(room_id) do
    %NewMeeting{startDateUTC: from, endDateUTC: to} = new_event

    try do
      with :valid_interval <- DateTimeHelper.valid_interval(from, to),
           :ok <-
             GenServer.call(
               __MODULE__,
               {:new_event, room_id, new_event},
               Application.fetch_env!(:roomz_caldav_to_generic_connector, :caldav_server_timeout)
             ) do
        :ok
      else
        {:error, reason} -> {:error, reason}
        :invalid_interval -> {:error, "The given interval was invalid: #{from}/#{to}"}
        x -> {:error, inspect(x)}
      end
    catch
      :exit, {:timeout, _} -> {:error, :timeout}
    end
  end

  def update_event(room_id, %UpdateMeeting{} = update_event) do
    %UpdateMeeting{startDateUTC: from, endDateUTC: to} = update_event

    try do
      with :valid_interval <- DateTimeHelper.valid_interval(from, to),
           :ok <-
             GenServer.call(
               __MODULE__,
               {:update_event, room_id, update_event},
               Application.fetch_env!(:roomz_caldav_to_generic_connector, :caldav_server_timeout)
             ) do
        :ok
      else
        {:error, reason} -> {:error, reason}
        x -> raise "Unknown error: #{inspect(x)}"
      end
    catch
      :exit, {:timeout, _} -> {:error, :timeout}
    end
  end

  # Server (callbacks)

  @impl true
  def init(%ServersState{} = init_args) do
    {:ok, init_args}
  end

  @impl true
  def handle_call({:get_image, room_id, meeting_id}, caller, state) do
    safe_forward_request(
      state,
      caller,
      room_id,
      {:get_image, caller, room_id, meeting_id}
    )
  end

  @impl true
  def handle_call(:get_rooms, _from, state) do
    %ServersState{servers: servers} = state

    rooms =
      servers
      |> Map.values()
      |> Stream.map(fn %ServerState{} = server -> server.rooms end)
      |> Stream.flat_map(&Map.values/1)
      |> Enum.uniq_by(fn %Room{id: x} -> x end)

    {:reply, {:ok, rooms}, state}
  end

  @impl true
  def handle_call({:get_events, room_id, interval}, caller, state) do
    safe_forward_request(
      state,
      caller,
      room_id,
      {:get_events, caller, room_id, interval}
    )
  end

  @impl true
  def handle_call({:new_event, room_id, new_event}, caller, state) do
    safe_forward_request(
      state,
      caller,
      room_id,
      {:new_event, caller, room_id, new_event}
    )
  end

  @impl true
  def handle_call({:update_event, room_id, update_event}, caller, state) do
    safe_forward_request(
      state,
      caller,
      room_id,
      {:update_event, caller, room_id, update_event}
    )
  end

  @impl true
  def handle_cast({:update_mappings, %ServerState{} = server}, state) do
    %ServerState{id: server_id, rooms: rooms} = server
    %ServersState{mappings: mappings, servers: servers} = state

    Logger.debug("Received new mappings of the server #{server_id}.")

    mappings =
      mappings
      |> Map.to_list()
      |> Stream.filter(fn {_, v} -> !String.equivalent?(v, server_id) end)
      |> Stream.concat(rooms |> Map.keys() |> Stream.map(fn x -> {x, server_id} end))
      |> Map.new()

    {:noreply,
     %ServersState{
       state
       | mappings: mappings,
         servers: Map.put(servers, server_id, server)
     }}
  end

  # Internals

  defp safe_forward_request(
         %ServersState{} = state,
         caller,
         room_id,
         request
       )
       when is_bitstring(room_id) do
    with %ServersState{servers: servers, mappings: mappings} <- state,
         {:ok, server_id} <- Map.fetch(mappings, room_id),
         {:ok, server} <- Map.fetch(servers, server_id) do
      try do
        [request_name | _] = Tuple.to_list(request)
        server_name = Server.server_name(server)

        Logger.debug("""
        Dispatching the request '#{request_name}' ...
          Server target: #{server_name}
          Server: #{inspect(self())}
          Request: #{request_name}
          Caller: #{inspect(caller)}
        """)

        GenServer.cast(
          {:global, server_name},
          request
        )

        {:noreply, state}
      catch
        :exit, {:timeout, _} -> {:reply, {:error, :timeout}, state}
      end
    else
      # INFO: Only forward the response from the specific server
      x -> {:reply, x, state}
    end
  end
end
