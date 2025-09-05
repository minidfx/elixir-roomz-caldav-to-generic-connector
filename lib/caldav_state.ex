defmodule CalDavState do
  use GuardedStruct

  guardedstruct do
    field(:clients, %{String.t() => CalDAVClient.Client.t()}, require: true)
  end
end
