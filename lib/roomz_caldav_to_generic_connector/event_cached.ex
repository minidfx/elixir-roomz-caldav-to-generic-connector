defmodule RoomzCaldavToGenericConnector.EventCached do
  use GuardedStruct

  guardedstruct do
    field(:id, String.t(), enforce: true)
    field(:room_id, String.t(), enforce: true)
    field(:etag, String.t(), enforce: true)
    field(:interval, Timex.Interval.t(), enforce: true)
    field(:uri, {:ok, URI.t()} | :none, enforce: true)

    field(:image, :none | {:ok, struct()} | :error, structs: Image, enforce: false)
  end
end
