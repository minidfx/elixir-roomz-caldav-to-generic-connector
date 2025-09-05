defmodule DateTimeHelper do
  import Guards

  @datetime_pattern "{ISO:Extended:Z}"
  @utc_timezone "Etc/UTC"

  def valid_interval(%DateTime{} = from, %DateTime{} = to)
      when is_utc(from) and
             is_utc(to) do
    if(Timex.before?(from, to), do: :valid_interval, else: :invalid_interval)
  end

  def valid_interval(_, _) do
    :invalid_interval
  end

  def to_string(%DateTime{} = datetime) when is_utc(datetime) do
    Timex.format!(datetime, @datetime_pattern)
  end

  def to_utc(%DateTime{} = datetime) when is_utc(datetime) do
    Timex.set(datetime, microsecond: 0)
  end

  def to_utc(datetime)
      when is_struct(datetime, DateTime) or
             is_struct(datetime, NaiveDateTime) do
    datetime
    |> Timex.Timezone.convert(@utc_timezone)
    |> Timex.set(microsecond: 0)
  end

  def parse(raw) when is_not_nil_or_empty_string(raw) do
    with {:ok, datetime} <- Timex.parse(raw, @datetime_pattern),
         datetime <- Timex.Timezone.convert(datetime, @utc_timezone) do
      {:ok, datetime}
    else
      {:error, reason} -> {:invalid_datetime, reason}
    end
  end

  def validator(:startDateUTC, value) when is_bitstring(value) do
    case parse(value) do
      {:ok, datetime} -> {:ok, :startDateUTC, datetime}
      {:invalid_datetime, reason} -> {:error, :startDateUTC, inspect(reason)}
    end
  end

  def validator(:endDateUTC, value) when is_bitstring(value) do
    case parse(value) do
      {:ok, datetime} -> {:ok, :endDateUTC, datetime}
      {:invalid_datetime, reason} -> {:error, :endDateUTC, inspect(reason)}
    end
  end

  def to_interval(%DateTime{} = from, %DateTime{} = to) when is_utc(from) and is_utc(to) do
    with %Timex.Interval{} = interval <-
           Timex.Interval.new(
             from: from,
             until: to,
             left_open: true,
             right_open: false
           ) do
      {:ok, interval}
    end
  end
end
