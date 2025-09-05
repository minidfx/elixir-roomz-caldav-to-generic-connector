defmodule UpdateMeeting do
  use GuardedStruct

  guardedstruct do
    field(:id, String.t(), enforce: true, derive: "sanitize(trim) validate(not_empty_string)")

    field(:startDateUTC, DateTime.t(),
      enforce: true,
      validator: {DatetimeValidator, :validator}
    )

    field(:endDateUTC, DateTime.t(), enforce: true, validator: {DatetimeValidator, :validator})
  end
end
