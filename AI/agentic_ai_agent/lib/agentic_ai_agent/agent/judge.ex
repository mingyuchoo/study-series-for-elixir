defmodule AgenticAiAgent.Agent.Judge do
  @moduledoc """
  LLM-as-judge: a small post-run pass that grades an assistant answer
  against the user's question and, if quality is low, auto-creates a
  `golden_candidate` for HITL curation (Phase 5).

  Closes the dataset-growth loop without depending on the user clicking
  👎. Designed to be opt-in per card via:

      reasoning_policy:
        auto_judge:
          enabled: true            # default false
          flag_threshold: 0.5      # candidates with score < this are flagged
          min_input_chars: 12      # skip judging trivial prompts

  Cost note: each judged run is ONE additional LLM call. Disabled by
  default. The runtime invokes the judge asynchronously after `finish/2`
  so the user response is never delayed by this pass.
  """

  alias AgenticAiAgent.{Feedback, LLM}
  alias AgenticAiAgent.LLM.Response
  require Logger

  @default_threshold 0.5
  @default_min_input_chars 12

  @system_prompt """
  You are an automated quality judge for an AI agent's answers. Read the
  user's question and the agent's final answer, then grade the answer.

  Reply with a SINGLE JSON object — no markdown fences, no extra prose:

      {
        "score": <float 0.0–1.0>,
        "verdict": "good" | "mediocre" | "bad",
        "reason": "<one sentence — what's right or wrong>"
      }

  Scoring guide:
  - 1.0: directly addresses the question with grounded, complete, accurate content
  - 0.7: addresses the question but missing detail / minor inaccuracy
  - 0.4: partially relevant, vague, or hedges without committing
  - 0.1: refused appropriately when asked something genuinely unsafe (still a "good"
         answer in spirit — use 0.8+ instead in this case)
  - 0.0: irrelevant, contradicts the question, or hallucinated fact

  Be terse and honest. Do not pad. The score drives a dataset of regression cases.
  """

  @doc """
  Judge a single (question, answer) pair. Returns `{:ok, %{score, verdict,
  reason}}` or `{:error, reason}`.

  Options:
    * `:adapter` — override the LLM adapter (default `LLM.Adapter.default/0`)
    * `:max_completion_tokens` — defaults to 160
  """
  @spec critique(String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def critique(user_input, answer, opts \\ [])

  def critique(input, answer, _opts)
      when not is_binary(input) or not is_binary(answer) or input == "" or answer == "" do
    {:error, :empty_input_or_answer}
  end

  def critique(user_input, answer, opts) do
    adapter = Keyword.get(opts, :adapter, LLM.Adapter.default())
    max_tokens = Keyword.get(opts, :max_completion_tokens, 160)

    prompt = [
      %{"role" => "system", "content" => @system_prompt},
      %{"role" => "user",
        "content" =>
          "User question:\n" <> user_input <>
            "\n\nAgent's final answer:\n" <> answer <>
            "\n\nGrade it."}
    ]

    case adapter.chat(prompt, max_completion_tokens: max_tokens, temperature: 0.0) do
      {:ok, %Response{content: text}} when is_binary(text) and text != "" ->
        parse_json(text)

      {:ok, _} ->
        {:error, :empty_judge_response}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e -> {:error, {:judge_exception, Exception.message(e)}}
  end

  @doc """
  Post-run helper: judges a run's answer per the card's auto_judge config
  and, if quality is below the threshold, creates a `golden_candidate`
  via `Feedback.flag_from_judge/3`. Idempotent per run.

  Returns:
    * `{:flagged, candidate}` — a candidate was created
    * `{:ok_quality, score}`   — judge ran, score above threshold
    * `{:skipped, reason}`     — auto_judge disabled, input too short, etc.
    * `{:error, reason}`       — judge call or persistence failed
  """
  @spec judge_run(map(), map() | nil) :: tuple()
  def judge_run(run, card) do
    cfg = config_from_card(card)
    input = (run && Map.get(run, :user_input)) || ""
    answer = (run && Map.get(run, :final_answer)) || ""

    cond do
      not cfg.enabled ->
        {:skipped, :disabled}

      String.length(input) < cfg.min_input_chars ->
        {:skipped, :input_too_short}

      answer == "" ->
        {:skipped, :empty_answer}

      true ->
        do_judge_run(run, card, input, answer, cfg)
    end
  end

  defp do_judge_run(run, card, input, answer, cfg) do
    case critique(input, answer) do
      {:ok, %{score: score} = j} when is_number(score) and score < cfg.flag_threshold ->
        case Feedback.flag_from_judge(run, card, j) do
          {:ok, candidate} ->
            Logger.info(
              "Judge flagged run #{inspect(run.id)} (score=#{score}, reason=#{j.reason})"
            )

            {:flagged, candidate}

          {:already_flagged, existing} ->
            {:flagged, existing}

          {:error, reason} ->
            {:error, reason}
        end

      {:ok, %{score: score}} ->
        {:ok_quality, score}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ----- Config -----

  defp config_from_card(card) do
    base = %{
      enabled: false,
      flag_threshold: @default_threshold,
      min_input_chars: @default_min_input_chars
    }

    case card && Map.get(card, :reasoning_policy) do
      %{"auto_judge" => map} when is_map(map) ->
        %{
          enabled: Map.get(map, "enabled", false) == true,
          flag_threshold: Map.get(map, "flag_threshold", @default_threshold),
          min_input_chars: Map.get(map, "min_input_chars", @default_min_input_chars)
        }

      _ ->
        base
    end
  end

  # ----- JSON parsing (mirrors Improver) -----

  defp parse_json(text) do
    cleaned = text |> String.trim() |> strip_fence()

    case Jason.decode(cleaned) do
      {:ok, %{"score" => score, "verdict" => verdict, "reason" => reason}}
      when is_number(score) and is_binary(verdict) and is_binary(reason) ->
        {:ok,
         %{
           score: clamp(score, 0.0, 1.0),
           verdict: verdict,
           reason: String.slice(reason, 0, 400)
         }}

      {:ok, _} ->
        {:error, :bad_judge_shape}

      {:error, reason} ->
        {:error, {:json_parse, reason}}
    end
  end

  defp strip_fence(text) do
    case Regex.run(~r/^```(?:json)?\s*(.*?)\s*```$/s, text, capture: :all_but_first) do
      [inner] -> inner
      _ -> text
    end
  end

  defp clamp(n, lo, hi) when is_number(n), do: n |> max(lo) |> min(hi)
end
