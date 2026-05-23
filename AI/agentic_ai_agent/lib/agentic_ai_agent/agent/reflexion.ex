defmodule AgenticAiAgent.Agent.Reflexion do
  @moduledoc """
  Self-critic for an in-flight ReAct loop. Implements the "Reflexion" half of
  `docs/ai-agent.md` §4 — at a configurable cadence the runtime asks the LLM
  to step out of the conversation and grade its own trajectory, then injects
  the critique as a system message into the next planning turn.

  The reflexion call is intentionally lightweight: no tools, a tight token
  budget, and a short structured-output instruction. It is *not* the main
  reasoning model — but in this scaffold we route it through the same
  Adapter for simplicity. Use a cheaper deployment for the critic in
  production by swapping the adapter via the `:reflexion_adapter` opt.
  """

  alias AgenticAiAgent.LLM.{Adapter, Response}

  @max_messages 20

  @critic_system_prompt """
  You are the self-critic for an autonomous AI agent. Read the trajectory
  below and produce a SHORT critique (under 100 words, plain text, no JSON).

  Cover, in this order:
    1. What is going well — one line.
    2. What is going off-track or inefficient — one line.
    3. Concrete next-step recommendation — one or two lines.

  Do NOT call any tool. Do NOT include code blocks. Be terse.
  """

  @doc """
  Run a critique pass over `messages` (the same list the planner would see).
  Returns `{:ok, critique_text}` or `{:error, reason}`.

  Opts:
    * `:adapter` — override LLM adapter (defaults to `Adapter.default/0`)
    * `:max_completion_tokens` — defaults to 240
  """
  @spec critique([map()], keyword()) :: {:ok, String.t()} | {:error, term()}
  def critique(messages, opts \\ []) do
    adapter = Keyword.get(opts, :adapter, Adapter.default())
    max_tokens = Keyword.get(opts, :max_completion_tokens, 240)

    prompt = [
      %{"role" => "system", "content" => @critic_system_prompt},
      %{"role" => "user",
        "content" => "Trajectory so far:\n\n" <> format_trajectory(messages)}
    ]

    case adapter.chat(prompt, max_completion_tokens: max_tokens) do
      {:ok, %Response{content: text}} when is_binary(text) and text != "" ->
        {:ok, String.trim(text)}

      {:ok, %Response{}} ->
        {:error, :empty_critique}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Build the system message that injects a critique into the next planner
  turn. Returns `nil` if the critique is empty/nil.
  """
  def to_system_message(nil), do: nil
  def to_system_message(""), do: nil

  def to_system_message(critique) when is_binary(critique) do
    %{
      "role" => "system",
      "content" =>
        "[SELF-CRITIQUE]\n" <>
          "An automated review of the trajectory so far. Treat as advice, " <>
          "not as ground truth.\n\n" <> critique
    }
  end

  # ----- Internal -----

  defp format_trajectory(messages) do
    messages
    |> Enum.take(-@max_messages)
    |> Enum.map_join("\n", fn m ->
      role = Map.get(m, "role", "?")
      content = Map.get(m, "content")
      summary =
        cond do
          is_binary(content) and content != "" -> String.slice(content, 0, 220)
          Map.has_key?(m, "tool_calls") -> "(requested " <> describe_tool_calls(m["tool_calls"]) <> ")"
          true -> "(empty)"
        end

      "[#{role}] " <> summary
    end)
  end

  defp describe_tool_calls(calls) when is_list(calls) do
    calls
    |> Enum.map(fn tc -> Map.get(tc, "function", %{})["name"] || tc[:name] || "?" end)
    |> Enum.join(", ")
  end

  defp describe_tool_calls(_), do: "tools"
end
