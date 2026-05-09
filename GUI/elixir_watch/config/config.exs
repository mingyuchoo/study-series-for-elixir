# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
import Config

scenic_debug? = System.get_env("SCENIC_DEBUG") in ["1", "true", "TRUE", "yes", "YES"]
window_title = System.get_env("SCENIC_WINDOW_TITLE", "elixir_watch")

viewport_size =
  case System.get_env("SCENIC_VIEWPORT_SIZE") do
    nil ->
      {480, 480}

    value ->
      case Regex.run(~r/^(\d+)x(\d+)$/, value) do
        [_, width, height] -> {String.to_integer(width), String.to_integer(height)}
        _ -> raise "SCENIC_VIEWPORT_SIZE must use WIDTHxHEIGHT format, for example 480x480"
      end
  end

# connect the app's asset module to Scenic
config :scenic, :assets, module: ElixirWatch.Assets

# Configure the main viewport for the Scenic application
config :elixir_watch, :viewport,
  name: :main_viewport,
  size: viewport_size,
  theme: :dark,
  default_scene: ElixirWatch.Scene.Home,
  drivers: [
    [
      module: Scenic.Driver.Local,
      name: :local,
      debug: scenic_debug?,
      window: [resizeable: false, title: window_title],
      on_close: :stop_system
    ]
  ]

# It is also possible to import configuration files, relative to this
# directory. For example, you can emulate configuration per environment
# by uncommenting the line below and defining dev.exs, test.exs and such.
# Configuration from the imported file will override the ones defined
# here (which is why it is important to import them last).
#
#     import_config "prod.exs"
