defmodule RoomzCaldavToGenericConnector.CalendearReaderResult do
  use GuardedStruct

  guardedstruct do
    field(:urn, String.t(), enforce: true)
    field(:display_name, String.t(), enforce: true)
  end
end
