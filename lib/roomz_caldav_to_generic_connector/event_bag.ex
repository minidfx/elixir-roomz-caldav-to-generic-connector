defmodule RoomzCaldavToGenericConnector.EventBag do
  use GuardedStruct

  alias CalDAVClient.ICalendar
  alias ICalendar.Event
  alias RoomzCaldavToGenericConnector.EventCached

  guardedstruct do
    field(:caldav_event, CalDAVClient.Event.t(), enforce: true)
    field(:ical_event, ICalendar.Event.t(), enforce: false)
    field(:events, struct(), structs: Event, enforce: false)
    field(:event_cached, struct(), structs: EventCached, enforce: false)
  end
end
