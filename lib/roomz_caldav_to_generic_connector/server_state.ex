defmodule RoomzCaldavToGenericConnector.ServerState do
  use GuardedStruct

  guardedstruct do
    field(:id, String.t(), enforce: true, derive: "sanitize(trim) validate(not_empty_string)")

    field(:rooms, %{String.t() => struct()}, enforce: true, structs: Room, default: %{})

    field(:uri, URI.t(),
      enforce: true,
      derive: "sanitize(trim) validate(not_empty_string) validate(uri)"
    )

    field(:username, String.t(),
      enforce: true,
      derive: "sanitize(trim) validate(not_empty_string)"
    )

    field(:client, CalDAVClient.Client.t(), enforce: false)
  end
end
