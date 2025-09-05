defmodule BasicAuth do
  @moduledoc """
  Functionality for providing Basic HTTP authentication.

  It is recommended to only use this module in production
  if SSL is enabled and enforced. See `Plug.SSL` for more
  information.

  Plug very close to the original `Plug.BasicAuth` but compares a string passed as environment variable.  
  This mechanism exists with the dotnet stack.
  """
  @behaviour Plug

  # Public

  @impl true
  def init(opts), do: Keyword.merge(opts, realm: Atom.to_string(RoomzCaldavToGenericConnector))

  @impl true
  def call(%Plug.Conn{} = conn, options \\ []) do
    username = Application.fetch_env!(:roomz_caldav_to_generic_connector, :basic_auth_username)
    password = Application.fetch_env!(:roomz_caldav_to_generic_connector, :basic_auth_password)

    with {user, pass} <- Plug.BasicAuth.parse_basic_auth(conn),
         true <- String.equivalent?(user, username),
         true <- String.equivalent?(pass, password) do
      conn
    else
      _ -> conn |> Plug.BasicAuth.request_basic_auth(options) |> Plug.Conn.halt()
    end
  end
end
