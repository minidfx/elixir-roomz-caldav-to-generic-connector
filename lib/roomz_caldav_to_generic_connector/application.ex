defmodule RoomzCaldavToGenericConnector.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    dns_query =
      Application.get_env(
        :roomz_caldav_to_generic_connector,
        :dns_cluster_query
      ) || :ignore

    fetch_event_image =
      Application.fetch_env!(
        :roomz_caldav_to_generic_connector,
        :prefetch_images
      )

    children = [
      RoomzCaldavToGenericConnectorWeb.Telemetry,
      {DNSCluster, query: dns_query},
      {Phoenix.PubSub, name: RoomzCaldavToGenericConnector.PubSub},
      # Start a worker by calling: RoomzCaldavToGenericConnector.Worker.start_link(arg)
      # {RoomzCaldavToGenericConnector.Worker, arg},
      # Start to serve requests, typically the last entry
      RoomzCaldavToGenericConnectorWeb.Endpoint,
      {RoomzCaldavToGenericConnector.ServersSupervisor, max_servers: 4},
      {RoomzCaldavToGenericConnector.ImageServer, start: fetch_event_image}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: RoomzCaldavToGenericConnector.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    RoomzCaldavToGenericConnectorWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
