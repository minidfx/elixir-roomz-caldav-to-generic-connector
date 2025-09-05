defmodule RoomzCaldavToGenericConnector.Event do
  @moduledoc """
  The event having the very close format for ROOMZ Connector.
  """

  use GuardedStruct

  guardedstruct do
    field(:meeting_id, String.t(),
      enforce: true,
      derive: "sanitize(trim) validate(not_empty_string)"
    )

    field(:subject, String.t(),
      enforce: true,
      derive: "sanitize(trim) validate(not_empty_string)"
    )

    field(:organizer_id, String.t(),
      enforce: true,
      derive: "sanitize(trim) validate(not_empty_string)"
    )

    field(:start_date_utc, DateTime.t(), enforce: true)
    field(:end_date_utc, DateTime.t(), enforce: true)
    field(:creation_date_utc, DateTime.t(), enforce: true)
    field(:is_private, boolean(), enforce: true)
    field(:is_cancelled, boolean(), enforce: true)
    field(:image_url, URI.t() | nil, enforce: false)
  end
end
