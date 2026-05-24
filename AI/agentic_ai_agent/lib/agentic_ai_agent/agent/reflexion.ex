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

  alias AgenticAiAgent.Agent.ReflexionInsights
  alias AgenticAiAgent.LLM.{Adapter, Response}
  alias AgenticAiAgent.Memory
  require Logger

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
      %{"role" => "user", "content" => "Trajectory so far:\n\n" <> format_trajectory(messages)}
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

  @doc """
  Persist a run's final critique as a long-term Memory entry so future
  runs can semantically retrieve the lesson via the existing Auto-RAG
  pipeline (`AgenticAiAgent.Agent.Context`).

  No-op when `note` is nil/empty — short runs that never triggered a
  reflexion don't pollute memory.

  Idempotent per-run: uses `overwrite_by_source` keyed on the run id, so
  rerunning persistence (e.g. on a runtime restart) updates the same row
  rather than duplicating it.

  Returns `:ok` on success or `{:error, reason}` if the embedding /
  insert fails. Callers should treat the error as advisory — failure to
  persist a reflexion must never break the parent run.
  """
  @spec persist_run_critique(map() | nil, map() | nil, String.t() | nil, keyword()) ::
          :ok | {:error, term()}
  def persist_run_critique(run, card, note, opts \\ [])

  def persist_run_critique(_run, _card, note, _opts) when note in [nil, ""], do: :ok

  def persist_run_critique(run, card, note, opts) when is_binary(note) do
    # Structured insight first — this is what the Improver consumes.
    # Memory persistence is best-effort and depends on embeddings being
    # configured, so we don't tie the two together. `opts` may carry
    # mid-run compliance metadata produced by
    # `AgenticAiAgent.Agent.ReflexionCompliance` — it's just forwarded.
    _ = ReflexionInsights.record(run, card, note, opts)

    user_input = run && Map.get(run, :user_input)
    run_id = run && Map.get(run, :id)
    card_slug = card && Map.get(card, :slug)

    content = format_memory_content(run_id, card_slug, user_input, note)

    opts = [
      kind: "reflexion",
      source: "run:#{run_id}",
      confidence: 0.7,
      sensitivity: "internal",
      retention_days: 30,
      update_rule: "overwrite_by_source",
      metadata: %{
        "run_id" => run_id,
        "card_slug" => card_slug,
        "user_input" => user_input
      }
    ]

    case Memory.remember(content, opts) do
      {:ok, _memory} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "Reflexion: failed to persist critique for run #{inspect(run_id)}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  rescue
    e ->
      Logger.warning("Reflexion: exception persisting critique: #{Exception.message(e)}")
      {:error, Exception.message(e)}
  end

  defp format_memory_content(run_id, card_slug, user_input, note) do
    user_input = user_input |> to_string() |> String.slice(0, 400)
    note = String.trim(note)
    short_run = run_id |> to_string() |> String.slice(0, 8)
    card_part = if card_slug, do: " · card #{card_slug}", else: ""

    "REFLEXION (run #{short_run}#{card_part}): User asked \"#{user_input}\".\nCritique: #{note}"
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
          is_binary(content) and content != "" ->
            String.slice(content, 0, 220)

          Map.has_key?(m, "tool_calls") ->
            "(requested " <> describe_tool_calls(m["tool_calls"]) <> ")"

          true ->
            "(empty)"
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
