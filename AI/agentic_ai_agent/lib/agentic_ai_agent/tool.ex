defmodule AgenticAiAgent.Tool do
  @moduledoc """
  Behaviour for agent tools. A tool is a pure-ish action the LLM can invoke:
  it has a typed contract (JSON Schema), a stated risk level, and a single
  `call/1` entry point that receives validated input and returns a structured
  result.

  Implements the Tool Contract row in `docs/eval.md` §6: `tool name`,
  `purpose`, `input schema`, `output schema`, `preconditions`, `side effects`,
  `failure modes`, and `retry policy`. The first six are pure metadata
  (returned by callbacks); `precheck/1` and `retry_policy/0` actually drive
  runtime behaviour.

  Tools should not raise on bad input — return `{:error, reason}` instead.
  Exceptions are still caught by the registry, but the explicit form lets
  the agent reflect on the failure.
  """

  @type risk_level :: :low | :medium | :high | :critical
  @type retry_policy :: %{
          optional(:max_retries) => non_neg_integer(),
          optional(:backoff_ms) => non_neg_integer(),
          optional(:retry_on) => [String.t()]
        }

  # ----- Required -----

  @callback name() :: String.t()
  @callback description() :: String.t()
  @callback input_schema() :: map()
  @callback output_schema() :: map()
  @callback risk_level() :: risk_level()
  @callback call(input :: map()) :: {:ok, map()} | {:error, term()}

  # ----- Optional metadata + behaviour -----

  @doc """
  Validate environmental / non-schema preconditions before `call/1` runs.
  Use for things like "an API key must be configured" that JSON Schema
  can't express. Returns `:ok` to proceed, `{:error, reason}` to abort
  the call (no retry).
  """
  @callback precheck(input :: map()) :: :ok | {:error, term()}

  @doc """
  Human-readable list of side effects this tool may produce. Pure-metadata,
  surfaced in the catalog UI and the LLM-facing description.
  """
  @callback side_effects() :: [String.t()]

  @doc """
  Known failure-mode slugs (must match entries in the Failure Mode Catalog).
  Used to seed retry policy defaults and to power related-test-case
  cross-references.
  """
  @callback failure_modes() :: [String.t()]

  @doc """
  Tool-level retry configuration:

      %{
        max_retries: non_neg_integer(),      # default 0 (no retry)
        backoff_ms: non_neg_integer(),       # default 250
        retry_on:   [failure_slug :: String.t()]
                                              # default []
      }

  The runtime classifies each failed call with `Failures.Detector` and
  retries only when the resulting slug appears in `retry_on`. Use this
  for transient failures (`tool_network_error`, `tool_timeout`,
  `llm_http_5xx` propagated by a tool, etc.). Side-effectful tools that
  aren't idempotent should leave `max_retries: 0`.
  """
  @callback retry_policy() :: retry_policy()

  @optional_callbacks precheck: 1, side_effects: 0, failure_modes: 0, retry_policy: 0
end
