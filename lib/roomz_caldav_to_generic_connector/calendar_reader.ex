defmodule RoomzCaldavToGenericConnector.CalendarReader do
  @moduledoc """
  Module responsible to read the XML calendar data.
  """

  alias RoomzCaldavToGenericConnector.CalendearReaderResult

  @spec read(tuple()) :: list(CalendearReaderResult.t())
  def read(saxy_tuple) when is_tuple(saxy_tuple) do
    saxy_tuple
    |> extract_responses()
    |> extract_calendar_data()
  end

  defp extract_responses({_multistatus, _, responses}), do: responses

  defp extract_calendar_data(responses) do
    extract_calendar_data(responses, [])
  end

  defp extract_calendar_data([{_, _, props} = _response | tail] = _responses, acc) do
    is_calendar =
      props
      |> Stream.map(&is_calendar?/1)
      |> Enum.any?()

    if(is_calendar) do
      # WARN: Can be improved by reading once the properties and save the values found into an bag struct.

      urn =
        props
        |> Stream.map(&extract_calendar_url/1)
        |> Stream.filter(&match?({:ok, _}, &1))
        |> Stream.map(fn {:ok, urn} -> urn end)
        |> Stream.take(1)
        |> Enum.at(0)

      display_name =
        props
        |> Stream.map(&extract_display_name/1)
        |> Stream.filter(&match?({:ok, _}, &1))
        |> Stream.map(fn {:ok, urn} -> urn end)
        |> Stream.take(1)
        |> Enum.at(0)

      extract_calendar_data(
        tail,
        [
          %CalendearReaderResult{
            urn: urn,
            display_name: display_name
          }
          | acc
        ]
      )
    else
      extract_calendar_data(tail, acc)
    end
  end

  defp extract_calendar_data([] = _responses, acc) do
    acc
  end

  defp is_calendar?(prop) do
    with {"d:propstat", _, propstat} <- prop,
         [{"d:prop", _, props}, _] <- propstat do
      props
      |> Stream.filter(fn
        {"d:resourcetype", _, _} -> true
        _ -> false
      end)
      |> Stream.flat_map(fn {_, _, types} -> types end)
      |> Enum.any?(fn
        {"cal:calendar", _, _} -> true
        _ -> false
      end)
    else
      _ -> false
    end
  end

  defp extract_display_name(prop) do
    with {"d:propstat", _, propstat} <- prop,
         [{"d:prop", _, props}, _] <- propstat do
      display_name =
        props
        |> Stream.filter(fn
          {"d:displayname", _, _} -> true
          _ -> false
        end)
        |> Stream.flat_map(fn {_, _, names} -> names end)
        |> Stream.take(1)
        |> Enum.at(0)

      {:ok, display_name}
    else
      _ -> :skip
    end
  end

  defp extract_calendar_url({"d:href", _, [url | _]}) do
    {:ok, url}
  end

  defp extract_calendar_url({"d:href", _, _}) do
    :skip
  end
end
