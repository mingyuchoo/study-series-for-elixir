defmodule AgenticAiAgentWeb.AgentProfiles do
  @moduledoc false

  @paths [
    "/images/avatars/avatar-01.png",
    "/images/avatars/avatar-02.png",
    "/images/avatars/avatar-03.png",
    "/images/avatars/avatar-04.png",
    "/images/avatars/avatar-05.png",
    "/images/avatars/avatar-06.png",
    "/images/avatars/avatar-07.png"
  ]

  def paths, do: @paths

  def valid_path?(path), do: path in @paths

  def default_path(%{metadata: %{"agent_avatar_path" => path}}) when is_binary(path) do
    if valid_path?(path), do: path, else: List.first(@paths)
  end

  def default_path(_card), do: List.first(@paths)

  def number(path) do
    path
    |> Path.basename(".png")
    |> String.replace("avatar-", "")
  end
end
