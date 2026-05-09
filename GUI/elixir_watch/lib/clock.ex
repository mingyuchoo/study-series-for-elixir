defmodule ElixirWatch.Clock do
  @moduledoc """
  Geometry helpers for the analog clock scene.
  """

  @type point :: {number(), number()}

  @spec local_time() :: Time.t()
  def local_time do
    {_date, time} = :calendar.local_time()
    Time.from_erl!(time)
  end

  @spec hand_angles(Time.t()) :: %{hour: float(), minute: float(), second: float()}
  def hand_angles(%Time{hour: hour, minute: minute, second: second}) do
    %{
      hour: (rem(hour, 12) + minute / 60 + second / 3600) * 30.0,
      minute: (minute + second / 60) * 6.0,
      second: second * 6.0
    }
  end

  @spec point_at(point(), number(), number()) :: point()
  def point_at({center_x, center_y}, radius, degrees) do
    radians = degrees * :math.pi() / 180

    {
      center_x + :math.sin(radians) * radius,
      center_y - :math.cos(radians) * radius
    }
  end

  @spec hand_line(point(), number(), number(), number()) :: {point(), point()}
  def hand_line(center, length, degrees, tail_length \\ 0) do
    {point_at(center, tail_length * -1, degrees), point_at(center, length, degrees)}
  end
end
