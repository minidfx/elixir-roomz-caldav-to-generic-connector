defmodule RoomzCaldavToGenericConnector.Room do
  use GuardedStruct

  guardedstruct do
    field(:id, String.t(), enforce: true, derive: "sanitize(trim) validate(not_empty_string)")

    field(:urn, String.t(), enforce: true, derive: "sanitize(trim) validate(not_empty_string)")

    field(:display_name, String.t(),
      enforce: true,
      derive: "sanitize(trim) validate(not_empty_string)"
    )
  end
end
