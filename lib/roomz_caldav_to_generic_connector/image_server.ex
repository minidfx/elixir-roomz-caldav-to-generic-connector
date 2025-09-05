defmodule RoomzCaldavToGenericConnector.ImageServer do
  use GenServer

  require Logger

  import Guards

  alias RoomzCaldavToGenericConnector.DownloadImagesRequest
  alias RoomzCaldavToGenericConnector.EventCached

  @allowed_image_extensions MapSet.new([".png", ".jpg", ".jpeg", ".bmp"])
  @allowed_mime_types MapSet.new(["image/jpg", "image/jpeg", "image/png", "image/bmp"])

  # Client

  def start_link(start: false) do
    Logger.notice(
      "Don't start the server because it is not required to fetch images of the events."
    )

    :ignore
  end

  def start_link(start: true) do
    Logger.notice("Starting the server to prefetch the images ...")
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def download_images(%DownloadImagesRequest{events: []}), do: :ok

  def download_images(%DownloadImagesRequest{} = request),
    do: GenServer.cast(__MODULE__, {:download_images, request})

  # Server (callbacks)

  @impl true
  def init(_init_args) do
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:download_images, %DownloadImagesRequest{} = request}, state) do
    %DownloadImagesRequest{events: events_cached, server: server} = request

    Logger.debug("Trying to download the event images ...")

    new_events_cached =
      events_cached
      |> Stream.dedup_by(fn %EventCached{id: x} -> x end)
      |> Task.async_stream(&filter_invalid_uri/1)
      # INFO: Filter out the success async task
      |> Stream.filter(&match?({:ok, _}, &1))
      |> Stream.map(fn {:ok, x} -> x end)
      |> Task.async_stream(&try_download_image/1,
        timeout:
          Timex.Duration.from_minutes(2)
          |> Timex.Duration.to_milliseconds(truncate: true),
        on_timeout: :kill_task
      )
      # INFO: Filter out the success async task
      |> Stream.filter(&match?({:ok, _}, &1))
      |> Stream.map(fn {:ok, x} -> x end)
      |> Task.async_stream(&make_roomz_image/1)
      # INFO: Filter out the success async task
      |> Stream.filter(&match?({:ok, _}, &1))
      |> Stream.map(fn {:ok, x} -> x end)
      |> Stream.map(fn
        {:skip, cache} -> cache
        {:ok, cache} -> cache
      end)
      |> Enum.to_list()

    GenServer.cast(server, {:update_images, new_events_cached})

    {:noreply, state}
  end

  # Internals

  defp filter_invalid_uri(%EventCached{uri: {:ok, uri}} = cache) do
    with {:ok, _} <- keep_image_with_allowed_extensions(uri) do
      {:ok, cache}
    else
      {:error, reason} ->
        Logger.notice(reason)
        {:skip, %EventCached{cache | image: :error}}
    end
  end

  defp filter_invalid_uri(%EventCached{uri: _} = cache) do
    Logger.notice("Invalid given URI.")
    {:skip, cache}
  end

  defp make_roomz_image({:skip, cache}), do: {:skip, cache}

  defp make_roomz_image({:ok, %EventCached{image: {:ok, image}} = cache}) do
    Logger.debug("Transforming the image for ROOMZ ...")

    with {:ok, image} <- Image.thumbnail(image, "1024x768", fit: :contain),
         {:ok, image} <- Image.to_colorspace(image, :bw),
         {:ok, image} <- Image.without_alpha_band(image, fn x -> {:ok, x} end) do
      {:ok, %EventCached{cache | image: {:ok, image}}}
    end
  end

  defp try_download_image({:skip, cache}), do: {:skip, cache}

  defp try_download_image({:ok, %EventCached{} = cache}) do
    %EventCached{uri: {:ok, uri}, room_id: room_id, id: event_id} = cache

    Logger.debug("Downloading the image #{URI.to_string(uri)} ...")

    with {:ok, %Req.Response{status: 200} = response} <- Req.get(uri),
         %Req.Response{body: body, headers: headers} <- response,
         {:ok, content_types} <- Map.fetch(headers, "content-type"),
         content_type <- hd(content_types) do
      Logger.notice(
        "Image downloaded for the room #{room_id} and the meeting_id #{event_id}: #{URI.to_string(uri)}"
      )

      if(MapSet.member?(@allowed_mime_types, content_type),
        do: {:ok, %EventCached{cache | image: Image.open(body)}},
        else: {:skip, %EventCached{cache | image: :error}}
      )
    else
      {:ok, %Req.Response{status: status}} ->
        Logger.notice(
          "Invalid status response received while trying to download the image from #{URI.to_string(uri)}: #{status}"
        )

        {:skip, %EventCached{cache | image: :error}}

      {:error, exception} ->
        Logger.notice(
          "An error occurred while trying to download the image from #{URI.to_string(uri)}: #{inspect(exception)}"
        )

        {:skip, %EventCached{cache | image: :error}}
    end
  end

  defp keep_image_with_allowed_extensions(%URI{} = uri) do
    with %URI{path: path} when is_not_nil_or_empty_string(path) <- uri,
         extension when is_not_nil_or_empty_string(extension) <- Path.extname(path) do
      if(MapSet.member?(@allowed_image_extensions, extension),
        do: {:ok, uri},
        else: {:error, "Invalid extension: #{extension}"}
      )
    else
      "" -> {:ok, uri}
      %URI{} -> {:error, "Invalid URI: #{URI.to_string(uri)}"}
      reason -> {:error, reason}
    end
  end
end
