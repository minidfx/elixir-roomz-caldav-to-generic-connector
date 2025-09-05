defmodule CalDavFactory do
  require Logger

  def create(max) when is_integer(max) do
    0..max
    |> Stream.map(&get_server/1)
    |> Stream.filter(&filter_server?/1)
    |> Stream.map(&Tuple.delete_at(&1, 0))
    |> Stream.map(&create_client/1)
  end

  defp get_server(index) do
    with {:ok, raw_uri} <-
           System.fetch_env("SERVER_URL_#{index}"),
         {:ok, uri} <- URI.new(raw_uri),
         {:ok, username} <-
           System.fetch_env("SERVER_USERNAME_#{index}"),
         {:ok, password} <-
           System.fetch_env("SERVER_PASSWORD_#{index}") do
      {:ok, uri, username, password}
    else
      :error -> {:skip, "Cannot read the server information for the index #{index}."}
    end
  end

  defp filter_server?({:error, reason}) do
    Logger.warning(reason)
    false
  end

  defp filter_server?({:skip, reason}) do
    Logger.notice(reason)
    false
  end

  defp filter_server?({:ok, _server, _username, _password}) do
    true
  end

  defp create_client({%URI{} = uri, username, password})
       when is_bitstring(username) and is_bitstring(password) do
    %CalDAVClient.Client{
      server_url: URI.to_string(uri),
      auth: %CalDAVClient.Auth.Basic{
        username: username,
        password: password
      }
    }
  end
end
