defmodule RoomzCaldavToGenericConnector.Room do
  use GuardedStruct

  alias RoomzCaldavToGenericConnector.EventCached

  guardedstruct do
    field(:id, String.t(), enforce: true, derive: "sanitize(trim) validate(not_empty_string)")

    field(:urn, String.t(), enforce: true, derive: "sanitize(trim) validate(not_empty_string)")

    field(:display_name, String.t(),
      enforce: true,
      derive: "sanitize(trim) validate(not_empty_string)"
    )

    field(:events_cached, %{String.t() => struct()},
      enforce: false,
      default: %{},
      structs: EventCached
    )
  end
end
