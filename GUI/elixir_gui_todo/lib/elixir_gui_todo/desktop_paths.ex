defmodule ElixirGuiTodo.DesktopPaths do
  @moduledoc false

  @app_dir "ElixirGuiTodo"

  def enabled? do
    System.get_env("ELIXIR_GUI_TODO_DESKTOP") in ["1", "true", "TRUE"]
  end

  def database_path do
    System.get_env("DATABASE_PATH") || Path.join(data_dir(), "elixir_gui_todo.db")
  end

  def secret_key_base_path do
    Path.join(data_dir(), "secret_key_base")
  end

  def secret_key_base do
    System.get_env("SECRET_KEY_BASE") || read_or_create_secret_key_base()
  end

  def data_dir do
    configured = System.get_env("ELIXIR_GUI_TODO_HOME")

    path =
      cond do
        configured && configured != "" -> configured
        match?({:win32, _}, :os.type()) -> windows_data_dir()
        :os.type() == {:unix, :darwin} -> macos_data_dir()
        true -> linux_data_dir()
      end

    File.mkdir_p!(path)
    path
  end

  defp read_or_create_secret_key_base do
    path = secret_key_base_path()

    case File.read(path) do
      {:ok, secret} ->
        String.trim(secret)

      {:error, :enoent} ->
        secret = :crypto.strong_rand_bytes(64) |> Base.encode64()
        File.write!(path, secret, [:write, :exclusive])
        secret

      {:error, reason} ->
        raise "could not read desktop secret key base at #{path}: #{inspect(reason)}"
    end
  rescue
    e in File.Error ->
      raise "could not initialize desktop data directory: #{Exception.message(e)}"
  end

  defp windows_data_dir do
    root =
      System.get_env("APPDATA") ||
        Path.join(System.user_home!(), "AppData/Roaming")

    Path.join(root, @app_dir)
  end

  defp macos_data_dir do
    Path.join([System.user_home!(), "Library", "Application Support", @app_dir])
  end

  defp linux_data_dir do
    root = System.get_env("XDG_DATA_HOME") || Path.join(System.user_home!(), ".local/share")
    Path.join(root, "elixir-gui-todo")
  end
end
