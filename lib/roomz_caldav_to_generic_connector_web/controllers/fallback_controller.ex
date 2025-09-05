defmodule RoomzCaldavToGenericConnectorWeb.FallbackController do
  use Phoenix.Controller, formats: [:json, :image]

  require Logger

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(
      json: RoomzCaldavToGenericConnectorWeb.ErrorJSON,
      html: RoomzCaldavToGenericConnectorWeb.ErrorHTML
    )
    |> render(:"404")
  end

  def call(conn, {:error, :unauthorized}) do
    conn
    |> put_status(403)
    |> put_view(
      json: RoomzCaldavToGenericConnectorWeb.ErrorJSON,
      html: RoomzCaldavToGenericConnectorWeb.ErrorHTML
    )
    |> render(:"403")
  end

  def call(conn, {:conflict, reason}) do
    Logger.notice(reason)

    conn
    |> put_status(409)
    |> put_view(
      json: RoomzCaldavToGenericConnectorWeb.ErrorJSON,
      html: RoomzCaldavToGenericConnectorWeb.ErrorHTML
    )
    |> render(:"409")
  end

  def call(conn, {:error, :timeout}) do
    Logger.warning("A timeout occurred while communicating with the servers.")

    conn
    |> put_status(504)
    |> put_view(
      json: RoomzCaldavToGenericConnectorWeb.ErrorJSON,
      html: RoomzCaldavToGenericConnectorWeb.ErrorHTML
    )
    |> render(:"504")
  end

  def call(conn, {:error, %{action: :required_fields} = error}) do
    conn
    |> put_status(400)
    |> put_view(
      json: RoomzCaldavToGenericConnectorWeb.ErrorJSON,
      html: RoomzCaldavToGenericConnectorWeb.ErrorHTML
    )
    |> render(:invalid_model, %{error: error})
  end

  def call(conn, {:error, reason}) when is_atom(reason) do
    call(conn, {:error, Atom.to_string(reason)})
  end

  def call(conn, {:error, reason}) when is_bitstring(reason) do
    Logger.warning(reason)

    conn
    |> put_status(400)
    |> put_view(
      json: RoomzCaldavToGenericConnectorWeb.ErrorJSON,
      html: RoomzCaldavToGenericConnectorWeb.ErrorHTML
    )
    |> render(:"400")
  end

  def call(conn, {:invalid_datetime, reason}) do
    Logger.warning(reason)

    conn
    |> put_status(400)
    |> put_view(
      json: RoomzCaldavToGenericConnectorWeb.ErrorJSON,
      html: RoomzCaldavToGenericConnectorWeb.ErrorHTML
    )
    |> render(:invalid_datetime, %{reason: reason})
  end
end
