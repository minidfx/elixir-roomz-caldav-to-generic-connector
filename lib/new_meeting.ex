defmodule NewMeeting do
  use GuardedStruct

  guardedstruct do
    field(:id, String.t(), enforce: true, derive: "sanitize(trim) validate(not_empty_string)")

    field(:subject, String.t(),
      enforce: false,
      derive: "sanitize(trim) validate(not_empty_string)"
    )

    field(:organizer_id, String.t(),
      enforce: false,
      derive: "sanitize(trim) validate(not_empty_string)"
    )

    field(:startDateUTC, DateTime.t(),
      enforce: true,
      validator: {DateTimeHelper, :validator}
    )

    field(:endDateUTC, DateTime.t(),
      enforce: true,
      validator: {DateTimeHelper, :validator}
    )
  end
end
