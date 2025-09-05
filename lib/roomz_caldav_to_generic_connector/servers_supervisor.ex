defmodule RoomzCaldavToGenericConnector.ServersSupervisor do
  use Supervisor

  require Logger

  alias RoomzCaldavToGenericConnector.Server
  alias RoomzCaldavToGenericConnector.Servers
  alias RoomzCaldavToGenericConnector.ServersState
  alias RoomzCaldavToGenericConnector.ServerState

  @default_upstream_timeout 10_000

  # Client

  def start_link(init_args) do
    Supervisor.start_link(__MODULE__, init_args, name: __MODULE__)
  end

  # Server (callbacks)

  @impl true
  def init(init_arg) do
    max_server = Keyword.get(init_arg, :max_servers, 1)
    server_timeout = Keyword.get(init_arg, :caldav_server_timeout, @default_upstream_timeout)

    Logger.debug("Will try to load up to #{max_server} servers ...")

    servers =
      max_server
      |> CalDavFactory.create()
      |> Stream.map(&by_server/1)
      |> Stream.filter(&match?({:ok, _}, &1))
      |> Stream.map(fn {:ok, x} -> x end)
      |> Enum.to_list()

    children =
      servers
      |> Stream.map(fn state ->
        Supervisor.child_spec({Server, state}, id: Server.server_name(state))
      end)
      |> Enum.to_list()

    servers_by_id =
      servers
      |> Stream.map(fn %ServerState{id: id} = server -> {id, server} end)
      |> Map.new()

    servers_client =
      {Servers,
       %ServersState{
         servers: servers_by_id,
         mappings: %{},
         caldav_server_timeout: server_timeout
       }}

    Logger.debug("#{Enum.count(servers)} servers loaded.")

    Supervisor.init([servers_client | children], strategy: :one_for_one, name: __MODULE__)
  end

  # Internals

  defp by_server(%CalDAVClient.Client{} = client) do
    with %CalDAVClient.Client{server_url: raw_base_server_url, auth: auth} <- client,
         base_server_url <- URI.new!(raw_base_server_url),
         %CalDAVClient.Auth.Basic{username: username} <- auth,
         {:ok, user_base_url} <- Server.create_user_url(base_server_url, username) do
      server = %ServerState{
        id: UUID.uuid4(),
        rooms: %{},
        uri: user_base_url,
        username: username,
        client: client
      }

      {:ok, server}
    else
      x ->
        {:error, inspect(x)}
    end
  end
end
