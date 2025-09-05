defmodule RoomzCaldavToGenericConnector.DownloadImagesRequest do
  use GuardedStruct

  alias RoomzCaldavToGenericConnector.EventCached

  guardedstruct do
    field(:server, reference(), enforce: true)
    field(:events, list(EventCached), enforce: true, default: [])
  end
end
