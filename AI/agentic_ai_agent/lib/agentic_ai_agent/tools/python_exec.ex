defmodule AgenticAiAgent.Tools.PythonExec do
  @moduledoc """
  Execute a Python snippet in an isolated sandbox and return stdout/stderr.
  Use this for arithmetic the calculator can't handle, data wrangling, or
  small scripts. Do NOT use for installing packages or accessing the network
  — the sandbox usually has `--network=none`.

  The default risk level is `:high`, which (per the card's safety policy)
  triggers a human-in-the-loop approval prompt before each call.
  """

  @behaviour AgenticAiAgent.Tool

  alias AgenticAiAgent.Sandbox

  @impl true
  def name, do: "python_exec"

  @impl true
  def description do
    base =
      "Run a short Python 3 script in an isolated sandbox. Returns stdout, stderr, and the exit status. The sandbox has no network access and a strict time/memory budget."

    case Sandbox.docker_available?() do
      true -> base <> " Running in Docker (`python:3.12-slim`)."
      false -> base <> " Falling back to host python3 with timeout-only isolation."
    end
  end

  @impl true
  def input_schema do
    %{
      "type" => "object",
      "required" => ["code"],
      "properties" => %{
        "code" => %{"type" => "string", "minLength" => 1, "maxLength" => 16_000},
        "timeout_ms" => %{"type" => "integer", "minimum" => 100, "maximum" => 30_000}
      }
    }
  end

  @impl true
  def output_schema do
    %{
      "type" => "object",
      "required" => ["exit_status", "stdout"],
      "properties" => %{
        "exit_status" => %{"type" => "integer"},
        "stdout" => %{"type" => "string"},
        "stderr" => %{"type" => "string"},
        "timed_out" => %{"type" => "boolean"},
        "strategy" => %{"type" => "string"},
        "duration_ms" => %{"type" => "integer"}
      }
    }
  end

  # Arbitrary code execution is high risk by default — the card's
  # `safety_policy.human_approval_required_for` picks this up automatically.
  @impl true
  def risk_level, do: :high

  @impl true
  def side_effects do
    [
      "Executes arbitrary Python 3 in an isolated sandbox.",
      "May write to its own /tmp; cannot reach the host filesystem.",
      "Sandbox container is destroyed after the call (no persistence)."
    ]
  end

  @impl true
  def failure_modes, do: ["tool_timeout", "tool_crash", "tool_invalid_input"]

  # Non-idempotent (running again may not produce the same effect).
  @impl true
  def retry_policy, do: %{max_retries: 0}

  @impl true
  def precheck(_input) do
    cond do
      Sandbox.docker_available?() -> :ok
      Sandbox.native_python_available?() -> :ok
      true -> {:error, "no sandbox available: install docker OR ensure python3 is on PATH"}
    end
  end

  @impl true
  def call(%{"code" => code} = input) when is_binary(code) do
    opts =
      case Map.get(input, "timeout_ms") do
        nil -> []
        ms when is_integer(ms) -> [timeout_ms: ms]
      end

    %Sandbox.Result{} = result = Sandbox.run_python(code, opts)

    {:ok,
     %{
       "exit_status" => result.exit_status,
       "stdout" => result.stdout,
       "stderr" => result.stderr,
       "timed_out" => result.timed_out?,
       "strategy" => Atom.to_string(result.strategy),
       "duration_ms" => result.duration_ms
     }}
  end

  def call(_), do: {:error, "missing 'code'"}
end
