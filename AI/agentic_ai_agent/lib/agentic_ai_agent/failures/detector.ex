defmodule AgenticAiAgent.Failures.Detector do
  @moduledoc """
  Classifies a `Runtime.fail/2` reason (or a tool error map) into a known
  failure-mode slug. Pure functions — no DB access. The caller looks the
  returned slug up in the catalog.

  Returns `{:ok, slug, summary}` for known shapes, or `:unknown` so the
  occurrence can still be recorded for later triage.
  """

  @type classification :: {:ok, slug :: String.t(), summary :: String.t()} | :unknown

  # ----- Runtime fail reasons -----

  @spec classify(any()) :: classification()

  def classify({:max_steps_exceeded, n}),
    do: {:ok, "max_steps_exceeded", "Hit ReAct step budget of #{n}."}

  def classify({:empty_response, _resp}),
    do: {:ok, "llm_empty_response", "Model returned neither content nor tool calls."}

  # LLM adapter errors (we wrap them in :llm_error tuples in Runtime)

  def classify({:llm_error, {:missing_config, key}}),
    do: {:ok, "llm_missing_config", "Adapter config missing: #{inspect(key)}."}

  def classify({:llm_error, {:http_error, status, _body}}) when status in 400..429,
    do: {:ok, "llm_http_4xx", "LLM HTTP #{status}."}

  def classify({:llm_error, {:http_error, status, _body}}) when status in 500..599,
    do: {:ok, "llm_http_5xx", "LLM HTTP #{status}."}

  def classify({:llm_error, {:http_error, status, _body}}),
    do: {:ok, "llm_http_other", "LLM HTTP #{status}."}

  def classify({:llm_error, {:transport_error, msg}}),
    do: {:ok, "llm_transport_error", "Transport failure: #{truncate(msg)}."}

  def classify({:llm_error, {:malformed_response, _}}),
    do: {:ok, "llm_malformed_response", "Adapter could not parse provider response."}

  def classify({:llm_error, other}),
    do: {:ok, "llm_other", "Unhandled LLM error: #{truncate(other)}"}

  # SubAgent delegated runs

  def classify({:sub_agent_failed, _reason}),
    do: {:ok, "sub_agent_failed", "Delegated sub-agent failed."}

  # Workflow

  def classify({:workflow_violation, from, to}),
    do: {:ok, "workflow_violation",
         "Planner attempted #{from} → #{to}, which the card's workflow graph does not allow."}

  def classify(:user_cancelled),
    do: {:ok, "user_cancelled", "User cancelled the run mid-execution."}

  def classify(_other), do: :unknown

  # ----- Tool call errors (passed from Runtime.execute_tool_and_record) -----

  @doc """
  Classify a single `Tools.Registry.call/2` error shape. Same return contract
  as `classify/1`.
  """
  @spec classify_tool_error(any()) :: classification()
  def classify_tool_error({:unknown_tool, name}),
    do: {:ok, "tool_unknown", "No tool named #{inspect(name)} in registry."}

  def classify_tool_error({:invalid_input, _errors}),
    do: {:ok, "tool_invalid_input", "Tool input failed JSON-Schema validation."}

  def classify_tool_error({:tool_crash, msg}),
    do: {:ok, "tool_crash", "Tool implementation raised: #{truncate(msg)}"}

  def classify_tool_error({:tool_throw, _}),
    do: {:ok, "tool_crash", "Tool implementation threw a non-exception value."}

  def classify_tool_error({:schema_error, msg}),
    do: {:ok, "tool_schema_error", "Schema compilation failed: #{truncate(msg)}"}

  def classify_tool_error({:precheck_failed, reason}),
    do: {:ok, "tool_precheck_failed", "Precondition failed: #{truncate(reason)}"}

  def classify_tool_error(msg) when is_binary(msg) do
    cond do
      msg =~ ~r/timed? out/i -> {:ok, "tool_timeout", msg}
      msg =~ ~r/denied by user/i -> {:ok, "tool_denied", msg}
      msg =~ ~r/network|connection|econnref|nxdomain/i ->
        {:ok, "tool_network_error", msg}

      true ->
        :unknown
    end
  end

  def classify_tool_error(_), do: :unknown

  # ----- Helpers -----

  defp truncate(value) do
    value
    |> case do
      v when is_binary(v) -> v
      v -> inspect(v)
    end
    |> String.slice(0, 200)
  end
end
