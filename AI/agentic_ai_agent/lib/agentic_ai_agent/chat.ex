defmodule AgenticAiAgent.Chat do
  @moduledoc """
  Thin orchestrator that ties a `Conversation` GenServer to the configured
  LLM adapter. Phase 3 keeps things simple: no tool calls, no ReAct loop.
  Phase 4 introduces `Agent.Runtime` which subsumes this module.
  """

  alias AgenticAiAgent.Conversation
  alias AgenticAiAgent.LLM.{Adapter, Response}

  @doc """
  Append a user message to the conversation, call the LLM, append the
  assistant reply, and return `{:ok, response}` or `{:error, reason}`.

  `opts` are forwarded to the adapter (`:temperature`, `:max_tokens`, ...).
  """
  @spec ask(GenServer.server(), String.t(), keyword()) ::
          {:ok, Response.t()} | {:error, term()}
  def ask(conversation, user_text, opts \\ []) do
    :ok = Conversation.append_user(conversation, user_text)
    ask_after_user(conversation, opts)
  end

  @doc """
  Call the LLM using whatever messages the conversation currently holds
  (assumes the caller has already appended the user turn). Appends the
  assistant reply on success.
  """
  @spec ask_after_user(GenServer.server(), keyword()) ::
          {:ok, Response.t()} | {:error, term()}
  def ask_after_user(conversation, opts \\ []) do
    messages = Conversation.for_llm(conversation)

    case Adapter.chat(messages, opts) do
      {:ok, %Response{content: content} = resp} when is_binary(content) ->
        :ok = Conversation.append_assistant(conversation, content)
        {:ok, resp}

      {:ok, %Response{} = resp} ->
        # Content-less response (e.g., the model only emitted tool_calls).
        # Phase 3 has no tool plumbing yet — surface as error.
        {:error, {:no_content, resp}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
