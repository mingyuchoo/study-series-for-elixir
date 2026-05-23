defmodule AgenticAiAgent.Agent.ToT do
  @moduledoc """
  Lite Tree of Thoughts. Implements the "task decomposition" half of
  `docs/ai-agent.md` §4 — instead of having the planner commit to a single
  next move, we ask the LLM to surface several candidate plans alongside
  self-ratings, then pick the highest-scored one.

  Depth-1 only: this is not a full tree expansion (true ToT spawns and
  prunes branches across multiple LLM round-trips, which is expensive).
  The single-call form is cheap enough to enable by default for hard tasks
  while keeping cost predictable.

  Activated by the card's `reasoning_policy.planning_strategy: "tot"`. The
  default remains `"react"`, in which case this module is not consulted.
  """

  alias AgenticAiAgent.LLM.{Adapter, Response}

  @planner_system_prompt """
  You are the planner for an autonomous AI agent. Instead of immediately
  acting, brainstorm 3 distinct candidate next moves and rate them.

  Return ONLY a JSON object of this exact shape (no prose, no markdown
  fences):

  {
    "candidates": [
      {"plan": "...", "score": 7, "rationale": "..."},
      {"plan": "...", "score": 5, "rationale": "..."},
      {"plan": "...", "score": 3, "rationale": "..."}
    ],
    "chosen_index": 0
  }

  Constraints:
    - plan: one short sentence describing the next action (tool call, or
      direct answer).
    - score: integer 1..10 — your honest estimate of expected usefulness.
    - rationale: <= 20 words.
    - chosen_index: 0-based index into candidates that you commit to.

  Be honest: if two candidates tie, pick the one that minimises tool
  calls.
  """

  @doc """
  Run a depth-1 brainstorm. Returns `{:ok, %{candidates: …, chosen: …}}`
  or `{:error, reason}` for either a transport failure or a malformed
  response.

  Opts: `:adapter` (default `Adapter.default/0`),
  `:max_completion_tokens` (default 600).
  """
  def brainstorm(messages, opts \\ []) do
    adapter = Keyword.get(opts, :adapter, Adapter.default())
    max_tokens = Keyword.get(opts, :max_completion_tokens, 600)

    prompt = [%{"role" => "system", "content" => @planner_system_prompt} | messages]

    case adapter.chat(prompt, max_completion_tokens: max_tokens) do
      {:ok, %Response{content: text}} when is_binary(text) and text != "" ->
        parse(text)

      {:ok, _} ->
        {:error, :empty_plan}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Build a system message that nudges the *actual* planner to follow the
  chosen plan. Returns `nil` if no plan picked.
  """
  def to_system_message(nil), do: nil

  def to_system_message(%{chosen: nil}), do: nil

  def to_system_message(%{chosen: %{"plan" => plan}, candidates: _}) when is_binary(plan) do
    %{
      "role" => "system",
      "content" =>
        "[SELECTED PLAN]\n" <>
          "After brainstorming alternatives, the chosen next move is:\n\n" <>
          plan <>
          "\n\nProceed with this plan unless a tool result invalidates it."
    }
  end

  def to_system_message(_), do: nil

  # ----- Parsing -----

  defp parse(text) do
    text
    |> strip_code_fence()
    |> Jason.decode()
    |> case do
      {:ok, %{"candidates" => candidates} = obj} when is_list(candidates) ->
        chosen_idx = obj["chosen_index"] || 0

        chosen =
          cond do
            is_integer(chosen_idx) and chosen_idx >= 0 and chosen_idx < length(candidates) ->
              Enum.at(candidates, chosen_idx)

            true ->
              # Fall back to the highest-scored candidate.
              Enum.max_by(candidates, &score_of/1, fn -> nil end)
          end

        {:ok, %{candidates: candidates, chosen: chosen, raw: obj}}

      {:ok, other} ->
        {:error, {:bad_plan_shape, other}}

      {:error, decode_error} ->
        {:error, {:malformed_plan_json, decode_error}}
    end
  end

  defp score_of(%{"score" => s}) when is_number(s), do: s
  defp score_of(_), do: 0

  # Strip ``` or ```json fences if the model returned a fenced block.
  defp strip_code_fence(text) do
    text
    |> String.trim()
    |> String.replace(~r/^```(?:json)?\s*/i, "")
    |> String.replace(~r/```$/, "")
    |> String.trim()
  end
end
