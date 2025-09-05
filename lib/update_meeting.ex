defmodule UpdateMeeting do
  use GuardedStruct

  guardedstruct do
    field(:id, String.t(), enforce: true, derive: "sanitize(trim) validate(not_empty_string)")

    field(:startDateUTC, DateTime.t(),
      enforce: true,
      validator: {DateTimeHelper, :validator}
    )

    field(:endDateUTC, DateTime.t(), enforce: true, validator: {DateTimeHelper, :validator})
  end
end
