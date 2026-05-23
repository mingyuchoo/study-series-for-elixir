defmodule AgenticAiAgent.LLM.Response do
  @moduledoc """
  Normalized response from an LLM adapter. `tool_calls` is an empty list
  for plain chat completions; it will carry structured tool invocations
  in Phase 4 (ReAct loop).
  """

  @type tool_call :: %{
          required(:id) => String.t(),
          required(:name) => String.t(),
          required(:arguments) => map()
        }

  @type usage :: %{
          optional(:prompt_tokens) => integer(),
          optional(:completion_tokens) => integer(),
          optional(:total_tokens) => integer()
        }

  @type t :: %__MODULE__{
          role: String.t(),
          content: String.t() | nil,
          tool_calls: [tool_call()],
          finish_reason: String.t() | nil,
          usage: usage() | nil,
          model: String.t() | nil,
          raw: map()
        }

  defstruct role: "assistant",
            content: nil,
            tool_calls: [],
            finish_reason: nil,
            usage: nil,
            model: nil,
            raw: %{}
end
