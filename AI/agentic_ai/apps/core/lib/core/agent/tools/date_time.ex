defmodule Core.Agent.Tools.DateTime do
  @moduledoc """
  현재 시간 및 날짜 연산을 위한 DateTime 도구.
  """

  def definition("get_current_time") do
    %{
      name: "get_current_time",
      description: "Get the current date and time. Optionally specify a timezone.",
      parameters: %{
        type: "object",
        properties: %{
          timezone: %{
            type: "string",
            description:
              "Timezone (e.g., 'Asia/Seoul', 'UTC', 'America/New_York'). Defaults to UTC."
          }
        },
        required: []
      }
    }
  end

  def definition(_), do: nil

  def execute("get_current_time", args) do
    timezone = Map.get(args, "timezone", "UTC")

    case DateTime.now(timezone) do
      {:ok, datetime} ->
        {:ok,
         %{
           datetime: DateTime.to_iso8601(datetime),
           timezone: timezone,
           formatted: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S %Z")
         }}

      {:error, :time_zone_not_found} ->
        # UTC로 폴백
        {:ok, datetime} = DateTime.now("Etc/UTC")

        {:ok,
         %{
           datetime: DateTime.to_iso8601(datetime),
           timezone: "UTC",
           formatted: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S %Z"),
           note: "Timezone '#{timezone}' not found, using UTC"
         }}
    end
  end
end
