defmodule ElixirWatch.Scene.Home do
  use Scenic.Scene
  require Logger

  alias ElixirWatch.Clock
  alias Scenic.Graph

  import Scenic.Primitives

  @tick_ms 1_000
  @background {10, 14, 18}
  @face {22, 28, 34}
  @bezel {56, 68, 78}
  @major_tick :white_smoke
  @minor_tick :slate_gray
  @label :light_gray
  @hour_hand :white
  @minute_hand :gainsboro
  @second_hand :tomato
  @center_cap :white_smoke

  @impl Scenic.Scene
  def init(scene, _param, _opts) do
    schedule_tick()

    scene =
      scene
      |> assign(:viewport_size, scene.viewport.size)
      |> draw_clock(Clock.local_time())

    {:ok, scene}
  end

  @impl true
  def handle_info(:tick, scene) do
    schedule_tick()
    {:noreply, draw_clock(scene, Clock.local_time())}
  end

  @impl Scenic.Scene
  def handle_input(event, _context, scene) do
    Logger.debug("Received event: #{inspect(event)}")
    {:noreply, scene}
  end

  defp schedule_tick do
    Process.send_after(self(), :tick, @tick_ms)
  end

  defp draw_clock(scene, time) do
    scene
    |> push_graph(build_graph(scene.assigns.viewport_size, time))
  end

  defp build_graph({width, height}, time) do
    side = min(width, height)
    center = {width / 2, height / 2}
    radius = side * 0.43
    angles = Clock.hand_angles(time)

    Graph.build(font: :roboto, font_size: max(18, side * 0.055))
    |> rect({width, height}, fill: @background)
    |> circle(radius + side * 0.045, fill: @bezel, translate: center)
    |> circle(radius,
      fill: @face,
      stroke: {max(2, side * 0.01), :light_slate_gray},
      translate: center
    )
    |> draw_ticks(center, radius, side)
    |> draw_labels(center, radius, side)
    |> draw_hands(center, radius, side, angles)
    |> circle(side * 0.025, fill: @center_cap, translate: center)
    |> circle(side * 0.012, fill: @second_hand, translate: center)
  end

  defp draw_ticks(graph, center, radius, side) do
    Enum.reduce(0..59, graph, fn tick, graph ->
      major? = rem(tick, 5) == 0
      degrees = tick * 6
      inner = radius - if(major?, do: side * 0.07, else: side * 0.035)
      outer = radius - side * 0.014
      width = if(major?, do: max(3, side * 0.012), else: max(1, side * 0.004))
      color = if(major?, do: @major_tick, else: @minor_tick)

      line(
        graph,
        {Clock.point_at(center, inner, degrees), Clock.point_at(center, outer, degrees)},
        stroke: {width, color},
        cap: :round
      )
    end)
  end

  defp draw_labels(graph, center, radius, side) do
    [{12, 0}, {3, 90}, {6, 180}, {9, 270}]
    |> Enum.reduce(graph, fn {label, degrees}, graph ->
      {x, y} = Clock.point_at(center, radius - side * 0.15, degrees)

      text(graph, Integer.to_string(label),
        fill: @label,
        text_align: :center,
        text_base: :middle,
        translate: {x, y}
      )
    end)
  end

  defp draw_hands(graph, center, radius, side, angles) do
    graph
    |> line(Clock.hand_line(center, radius * 0.5, angles.hour, side * 0.035),
      stroke: {max(6, side * 0.025), @hour_hand},
      cap: :round
    )
    |> line(Clock.hand_line(center, radius * 0.72, angles.minute, side * 0.045),
      stroke: {max(4, side * 0.016), @minute_hand},
      cap: :round
    )
    |> line(Clock.hand_line(center, radius * 0.82, angles.second, side * 0.08),
      stroke: {max(2, side * 0.006), @second_hand},
      cap: :round
    )
  end
end
