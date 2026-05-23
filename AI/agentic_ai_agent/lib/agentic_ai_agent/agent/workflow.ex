defmodule AgenticAiAgent.Agent.Workflow do
  @moduledoc """
  Runtime view of an agentic card's `workflow_graphs[0]`. Used to validate
  the planner's state transitions and detect when the loop has entered a
  terminal state. See `docs/eval.md` §7.

  Two enforcement modes:

    * **enforce: false** (default) — graph is documentation. Invalid
      transitions are logged in the step payload but don't stop the run.
    * **enforce: true** — invalid transitions fail the run with reason
      `{:invalid_transition, from, to}`. The runtime always allows
      transitions to `failed` / `cancelled` regardless (so unrecoverable
      errors and user cancels are never blocked).

  Built from the *first* workflow graph attached to the card. If the card
  has none, a default ReAct graph is used.
  """

  alias AgenticAiAgent.Design.WorkflowGraph

  defstruct name: nil,
            transitions: %{},
            terminal_states: [],
            approval_points: [],
            enforce?: false,
            allowed_actions: %{},
            required_evidence: %{}

  @unconditional_terminal ~w(failed cancelled)

  defp default_react_graph do
    %__MODULE__{
      name: "default_react_loop",
      transitions: %{
        "idle" => ["planning"],
        "planning" => ["acting", "done"],
        "acting" => ["observing", "awaiting_approval"],
        "observing" => ["reflecting"],
        "reflecting" => ["planning", "done", "failed"],
        "awaiting_approval" => ["acting", "failed"]
      },
      terminal_states: ["done", "failed", "cancelled"],
      approval_points: ["awaiting_approval"]
    }
  end

  @doc """
  Build a `%Workflow{}` from a card (which may have several workflow_graphs).
  Picks the first one. Falls back to the default ReAct graph if none.
  """
  def from_card(nil), do: default_react_graph()

  def from_card(card) do
    case card.workflow_graphs do
      [%WorkflowGraph{} = wf | _] -> from_graph(wf)
      _ -> default_react_graph()
    end
  end

  defp from_graph(%WorkflowGraph{} = wf) do
    %__MODULE__{
      name: wf.name,
      transitions: wf.transitions || %{},
      terminal_states: Enum.uniq((wf.terminal_states || []) ++ @unconditional_terminal),
      approval_points: wf.approval_points || [],
      enforce?: wf.enforce == true,
      allowed_actions: wf.allowed_actions || %{},
      required_evidence: wf.required_evidence || %{}
    }
  end

  @doc """
  Returns the default ReAct graph used when no card is attached.
  """
  def default, do: default_react_graph()

  @doc """
  Returns `:ok` / `{:error, {:invalid_transition, from, to}}`.

  Transitions into `failed` / `cancelled` are always allowed; transitions
  out of an unknown state are allowed (so we don't trip during bootstrap).
  """
  def validate(%__MODULE__{} = wf, from, to) do
    from = to_string(from)
    to = to_string(to)

    cond do
      to in @unconditional_terminal -> :ok
      from == to -> :ok
      Map.has_key?(wf.transitions, from) == false -> :ok
      to in Map.get(wf.transitions, from, []) -> :ok
      true -> {:error, {:invalid_transition, from, to}}
    end
  end

  @doc "Whether `state` is terminal."
  def terminal?(%__MODULE__{terminal_states: ts}, state),
    do: to_string(state) in ts

  @doc "Whether `state` is an approval point."
  def approval_point?(%__MODULE__{approval_points: aps}, state),
    do: to_string(state) in aps

  @doc """
  Whether the graph wants the runtime to fail-fast on invalid transitions.
  """
  def enforce?(%__MODULE__{enforce?: v}), do: v

  @doc "Plain map view for telemetry / step payloads."
  def to_map(%__MODULE__{} = wf) do
    %{
      "name" => wf.name,
      "enforce" => wf.enforce?,
      "terminal_states" => wf.terminal_states,
      "approval_points" => wf.approval_points
    }
  end
end
