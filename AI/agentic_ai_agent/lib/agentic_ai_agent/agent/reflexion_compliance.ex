defmodule AgenticAiAgent.Agent.ReflexionCompliance do
  @moduledoc """
  Tracks whether the agent is actually acting on its own self-critic's
  guidance during a single run.

  ## The gap this closes

  `AgenticAiAgent.Agent.Reflexion` produces a critique every N
  iterations and the runtime injects it as a `[SELF-CRITIQUE]` system
  message into the next planner turn. But nothing checks whether the
  agent **heeded** the critique. If the planner ignores the same
  guidance N turns in a row, the original mechanism just keeps
  whispering it gently.

  This module closes that gap with a simple but effective signal:

    * Each new critique is reduced to a coarse `theme` via
      `AgenticAiAgent.Agent.ReflexionInsights.extract_theme/1`.
    * The runtime keeps a per-run history of those themes.
    * When the most recent K critiques share the same non-nil theme,
      the runtime **escalates**: the next planner turn receives a
      strongly-worded system message instead of the gentle advisory
      one. The compliance outcome (`"escalated"`, `"ignored"`,
      `"complied"`) is persisted on the `reflexion_insights` row.

  This is the *cheapest* mid-run self-healing signal in the codebase
  — it adds zero LLM calls and does not change any existing
  trajectory unless the agent is provably stuck.

  ## Decision shape

      check_themes([theme | _] = history, threshold)
      #=> :ok
      #   the last `threshold-1` themes are NOT all the same as `theme`
      #   (or `theme` is nil → no signal extracted yet)
      # OR
      #=> {:escalate, theme, count}
      #   the last `count >= threshold` themes are all `theme`
  """

  @default_threshold 2

  @doc """
  Decide compliance given a run's recent critique-theme history
  (newest-first).

  `threshold` is the number of *consecutive* same-theme critiques that
  trip an escalation. Default 2 — anything lower would escalate on the
  very first critique, anything higher delays the runtime response.

  Returns `:ok` when no escalation is warranted, or
  `{:escalate, theme, count}` when the most recent `count >= threshold`
  critiques all flagged the same theme.

  Pure function — no IO, no state. Callers (`Runtime`) own the history
  list and update it after each `Reflexion.critique/2` call.
  """
  @spec check_themes([String.t() | nil], pos_integer()) ::
          :ok | {:escalate, String.t(), pos_integer()}
  def check_themes(history, threshold \\ @default_threshold)

  def check_themes([], _), do: :ok
  def check_themes([nil | _], _), do: :ok

  def check_themes([theme | _] = history, threshold)
      when is_binary(theme) and is_integer(threshold) and threshold >= 1 do
    same_run = consecutive_prefix(history, theme)

    if same_run >= threshold do
      {:escalate, theme, same_run}
    else
      :ok
    end
  end

  defp consecutive_prefix([h | _] = list, target) when h == target do
    Enum.take_while(list, &(&1 == target)) |> length()
  end

  defp consecutive_prefix(_, _), do: 0

  @doc """
  Render the escalated system message to inject ahead of the regular
  `[SELF-CRITIQUE]` block. The message is firm, names the recurring
  theme, and instructs the planner to pivot strategy on the very next
  step.

  Returns `nil` for an empty/nil theme so callers can pipe through
  without branching.
  """
  @spec escalation_system_message(String.t() | nil, pos_integer()) ::
          map() | nil
  def escalation_system_message(nil, _), do: nil

  def escalation_system_message(theme, count)
      when is_binary(theme) and is_integer(count) and count >= 1 do
    %{
      "role" => "system",
      "content" =>
        "[ESCALATED SELF-CRITIQUE — #{count}× IN A ROW]\n" <>
          "The self-critic has flagged the SAME weakness — `#{theme}` — " <>
          "across the last #{count} reflexion checks. The agent has been " <>
          "ignoring the prior advisory critique. STOP repeating the same " <>
          "pattern. On this turn you MUST take a DIFFERENT action class " <>
          "(e.g. retrieve before tool calls, switch strategy, or finalize " <>
          "with what you already have). This is not advice."
    }
  end

  @doc """
  Map a runtime compliance state at end-of-run to the value persisted
  in `reflexion_insights.compliance_outcome`.

  Inputs are the final `noncompliance_count` and `escalated?` flag the
  Runtime carried in its state. Returns one of:

    * `"escalated"` — escalation fired during the run
    * `"ignored"`   — same-theme recurred at least once but didn't
                      reach threshold
    * `"complied"`  — never recurred (count == 0)
    * `nil`         — no critique produced at all (theme history empty)
  """
  @spec outcome_for_persist(non_neg_integer(), boolean(), boolean()) ::
          String.t() | nil
  def outcome_for_persist(_count, true, _any_critique), do: "escalated"
  def outcome_for_persist(_count, _escalated, false), do: nil
  def outcome_for_persist(0, false, true), do: "complied"
  def outcome_for_persist(count, false, true) when count > 0, do: "ignored"
end
