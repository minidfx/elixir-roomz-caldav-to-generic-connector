defmodule RoomzCaldavToGenericConnector.EventsBag do
  use GuardedStruct

  alias RoomzCaldavToGenericConnector.EventBag
  alias RoomzCaldavToGenericConnector.EventCached

  guardedstruct do
    field(:context_time, DateTime.t(), enforce: true)
    field(:room_id, String.t(), enforce: true)
    field(:interval, Timex.Interval.t(), enforce: true)
    field(:caldav_events, list(CalDAVClient.Event.t()), enforce: true)

    field(:events_cached, %{String.t() => struct()},
      enforce: false,
      default: %{},
      structs: EventCached
    )

    field(:events, list(struct()), structs: EventBag, enforce: false, default: [])
  end
end
