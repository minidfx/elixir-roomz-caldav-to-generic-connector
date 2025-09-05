defmodule Guards do
  defguard is_utc(datetime)
           when is_struct(datetime, DateTime) and
                  is_map_key(datetime, :time_zone) and
                  not is_nil(datetime.time_zone) and
                  datetime.time_zone == "Etc/UTC"

  defguard is_not_nil_or_empty_string(string)
           when not is_nil(string) and
                  is_bitstring(string) and
                  bit_size(string) > 0
end
