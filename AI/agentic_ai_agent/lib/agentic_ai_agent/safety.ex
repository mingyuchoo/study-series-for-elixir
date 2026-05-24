defmodule AgenticAiAgent.Safety do
  @moduledoc """
  Static safety audit for agentic card edits. Detects "alignment drift"
  patterns where a proposed YAML quietly loosens guardrails relative to
  the current card.

  This is a **pure function** — no LLM call, no DB read — so it can be
  invoked cheaply at proposal-generation time as a deterministic gate
  before the scheduler considers auto-promotion.

  Rules surfaced today (see `rules/0` for the catalog):

  | severity | rule | description |
  |----------|------|-------------|
  | high     | approval_removed_for_high | `safety_policy.human_approval_required_for` dropped `"high"` |
  | high     | deny_list_shrunk         | `tool_policy.deny` lost entries |
  | high     | high_risk_tool_added     | `tool_policy.allow` gained a known-risky tool |
  | high     | workflow_acting_widened  | `workflow_graphs[].allowed_actions.acting` removed restrictions |
  | warn     | output_contract_regressed | `output_contract.cite_sources` silently turned off |

  Verdict:
    * `:pass` — no violations
    * `:warn` — only warnings (no `severity: "high"` items)
    * `:fail` — at least one `severity: "high"` violation
  """

  @known_high_risk_tools ~w(python_exec)

  @doc """
  Audit a proposed card body against the current one. Both arguments are
  raw YAML strings.

  Returns `{:ok, %{score, violations, warnings, verdict}}` on success.
  Failure to parse either YAML returns `{:ok, %{score: 0.5, verdict: :warn,
  violations: [], warnings: [<parse warning>]}}` — we still complete the
  audit so the proposer flow isn't blocked, but operator visibility is
  clear.
  """
  @spec audit_card(String.t() | nil, String.t() | nil) :: {:ok, map()}
  def audit_card(original_yaml, proposed_yaml) do
    with {:ok, original} <- parse(original_yaml || "{}"),
         {:ok, proposed} <- parse(proposed_yaml || "{}") do
      issues =
        for rule <- rules(),
            issue = rule.check.(original, proposed),
            not is_nil(issue),
            do: Map.put(issue, :rule, rule.id)

      {violations, warnings} = Enum.split_with(issues, &(&1.severity == "high"))

      verdict =
        cond do
          violations != [] -> :fail
          warnings != [] -> :warn
          true -> :pass
        end

      score =
        case verdict do
          :pass -> 1.0
          :warn -> 0.7
          :fail -> 0.0
        end

      {:ok,
       %{
         score: score,
         verdict: verdict,
         violations: violations,
         warnings: warnings
       }}
    else
      _ ->
        {:ok,
         %{
           score: 0.5,
           verdict: :warn,
           violations: [],
           warnings: [
             %{rule: "parse_failure", severity: "warn", detail: "YAML parse failed; audit incomplete"}
           ]
         }}
    end
  end

  @doc "List of audit rules. Each rule has an id and a `check.(original, proposed)` function."
  def rules do
    [
      %{
        id: "approval_removed_for_high",
        check: fn original, proposed ->
          before_list = get_in(original, ["safety_policy", "human_approval_required_for"]) || []
          after_list = get_in(proposed, ["safety_policy", "human_approval_required_for"]) || []

          if "high" in before_list and "high" not in after_list do
            %{
              severity: "high",
              detail:
                "safety_policy.human_approval_required_for dropped \"high\" — high-risk tool calls would auto-execute."
            }
          end
        end
      },
      %{
        id: "deny_list_shrunk",
        check: fn original, proposed ->
          before_deny = get_in(original, ["tool_policy", "deny"]) || []
          after_deny = get_in(proposed, ["tool_policy", "deny"]) || []
          removed = before_deny -- after_deny

          if removed != [] do
            %{
              severity: "high",
              detail:
                "tool_policy.deny lost #{inspect(removed)} — previously-denied tools would become callable."
            }
          end
        end
      },
      %{
        id: "high_risk_tool_added",
        check: fn original, proposed ->
          before_allow = get_in(original, ["tool_policy", "allow"]) || []
          after_allow = get_in(proposed, ["tool_policy", "allow"]) || []
          added = after_allow -- before_allow
          risky = added |> Enum.filter(&(&1 in @known_high_risk_tools))

          if risky != [] do
            %{
              severity: "high",
              detail:
                "tool_policy.allow gained known-risky tool(s) #{inspect(risky)}. Verify safety_policy still requires approval."
            }
          end
        end
      },
      %{
        id: "workflow_acting_widened",
        check: fn original, proposed ->
          before_acting = workflow_acting_allowed(original)
          after_acting = workflow_acting_allowed(proposed)

          # Original constrained acting to a list; proposed removed the
          # constraint entirely (nil) or shrank deny by going to wildcard.
          cond do
            is_list(before_acting) and before_acting != [] and is_nil(after_acting) ->
              %{
                severity: "high",
                detail:
                  "workflow_graphs[*].allowed_actions.acting removed — acting state no longer restricts tool calls."
              }

            is_list(before_acting) and is_list(after_acting) and "*" in after_acting and "*" not in before_acting ->
              %{
                severity: "high",
                detail:
                  "workflow_graphs[*].allowed_actions.acting widened to wildcard \"*\" — every tool is now allowed during acting."
              }

            true ->
              nil
          end
        end
      },
      %{
        id: "output_contract_regressed",
        check: fn original, proposed ->
          before_cite = get_in(original, ["output_contract", "cite_sources"])
          after_cite = get_in(proposed, ["output_contract", "cite_sources"])

          if before_cite == true and after_cite != true do
            %{
              severity: "warn",
              detail:
                "output_contract.cite_sources is no longer true — generated answers may stop citing sources."
            }
          end
        end
      }
    ]
  end

  # ----- Internals -----

  defp parse(yaml) when is_binary(yaml) do
    case YamlElixir.read_from_string(yaml) do
      {:ok, m} when is_map(m) -> {:ok, m}
      _ -> :error
    end
  end

  defp parse(_), do: :error

  # Inspect each workflow_graphs entry; return the first non-empty
  # `allowed_actions.acting` list if any, else nil. (Most cards have at
  # most one workflow graph.)
  defp workflow_acting_allowed(card) do
    graphs = Map.get(card, "workflow_graphs") || []

    Enum.find_value(graphs, fn graph ->
      get_in(graph, ["allowed_actions", "acting"])
    end)
  end
end
