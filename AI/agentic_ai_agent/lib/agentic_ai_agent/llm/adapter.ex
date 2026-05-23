defmodule AgenticAiAgent.LLM.Adapter do
  @moduledoc """
  Behaviour every LLM provider must implement. Messages follow the
  OpenAI-style shape:

      %{"role" => "system" | "user" | "assistant" | "tool", "content" => string,
        # optional, present on assistant turns that requested tools:
        "tool_calls" => [%{"id" => ..., "type" => "function",
                            "function" => %{"name" => ..., "arguments" => json_string}}],
        # optional, present on tool turns:
        "tool_call_id" => ...}

  Opts the adapter MUST accept (extra opts may be ignored):

    * `:tools` — list of tool descriptors (`Tools.Registry.descriptors/0`).
      The adapter is responsible for translating to the provider's format.
    * `:tool_choice` — `"auto"` | `"none"` | `%{"name" => ...}`.
    * `:temperature` — float, default per-adapter.
    * `:max_tokens` — integer.
    * `:system` — string. If provided AND messages does not start with
      a system role, the adapter prepends it.
  """

  alias AgenticAiAgent.LLM.Response

  @callback chat(messages :: [map()], opts :: keyword()) ::
              {:ok, Response.t()} | {:error, term()}

  @doc "Returns the configured default adapter module."
  def default do
    Application.get_env(:agentic_ai_agent, :llm_adapter, AgenticAiAgent.LLM.AzureOpenAI)
  end

  @doc "Convenience: call the default adapter."
  def chat(messages, opts \\ []) do
    default().chat(messages, opts)
  end
end
