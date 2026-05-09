defmodule ElixirWatch.ClockTest do
  use ExUnit.Case, async: true

  alias ElixirWatch.Clock

  describe "hand_angles/1" do
    test "places every hand at 12 o'clock for midnight" do
      assert Clock.hand_angles(~T[00:00:00]) == %{hour: 0.0, minute: 0.0, second: 0.0}
    end

    test "includes minute and second progress in the hour hand" do
      assert Clock.hand_angles(~T[06:30:00]).hour == 195.0
      assert_in_delta Clock.hand_angles(~T[03:15:30]).hour, 97.75, 0.001
    end

    test "includes second progress in the minute hand" do
      assert Clock.hand_angles(~T[00:30:00]).minute == 180.0
      assert Clock.hand_angles(~T[00:15:30]).minute == 93.0
    end
  end

  describe "point_at/3" do
    test "uses 0 degrees as twelve o'clock and advances clockwise" do
      assert_point(Clock.point_at({100, 100}, 50, 0), {100, 50})
      assert_point(Clock.point_at({100, 100}, 50, 90), {150, 100})
      assert_point(Clock.point_at({100, 100}, 50, 180), {100, 150})
      assert_point(Clock.point_at({100, 100}, 50, 270), {50, 100})
    end
  end

  defp assert_point({actual_x, actual_y}, {expected_x, expected_y}) do
    assert_in_delta actual_x, expected_x, 0.001
    assert_in_delta actual_y, expected_y, 0.001
  end
end
