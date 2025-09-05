defmodule RoomzCaldavToGenericConnector.ServersState do
  use GuardedStruct

  alias RoomzCaldavToGenericConnector.ServersState

  guardedstruct do
    field(:servers, %{String.t() => struct()}, enforce: true, structs: ServersState)
    field(:mappings, %{String.t() => String.t()}, enforce: true)
    field(:caldav_server_timeout, non_neg_integer(), enforce: true)
  end
end
