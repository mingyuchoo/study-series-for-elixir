defmodule ElixirGuiTodo.Repo do
  use Ecto.Repo,
    otp_app: :elixir_gui_todo,
    adapter: Ecto.Adapters.SQLite3
end
