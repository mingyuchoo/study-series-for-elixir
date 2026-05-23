defmodule AgenticAiAgent.Agent.Charter do
  @moduledoc """
  Runtime operating charter for the agent.

  Loads `AGENTS.md` from the project root at compile time via
  `@external_resource`, so the file becomes part of the BEAM artifact and
  edits trigger automatic recompilation in dev. Three call sites prepend
  `text/0` to the system prompt:

    * `AgenticAiAgentWeb.ChatLive` — user-facing chat
    * `AgenticAiAgent.Eval` — rubric-based evaluation runs
    * `AgenticAiAgent.Agent.Runtime` — sub-agents spawned by `delegate`

  If `AGENTS.md` is missing the charter is silently empty and `prepend/1`
  becomes a no-op.
  """

  @charter_path Path.expand("../../../AGENTS.md", __DIR__)
  @external_resource @charter_path

  @charter (case File.read(@charter_path) do
              {:ok, body} -> String.trim(body)
              {:error, _} -> ""
            end)

  @doc "The raw charter text. Empty string if AGENTS.md is missing."
  @spec text() :: String.t()
  def text, do: @charter

  @doc """
  Prepend the charter to a system prompt body, separated by a horizontal rule.
  An empty/nil body returns the charter alone. An empty charter returns the
  body unchanged.
  """
  @spec prepend(String.t() | nil) :: String.t()
  def prepend(body) do
    body = body |> to_string() |> String.trim()

    case {@charter, body} do
      {"", b} -> b
      {c, ""} -> c
      {c, b} -> c <> "\n\n---\n\n" <> b
    end
  end
end
