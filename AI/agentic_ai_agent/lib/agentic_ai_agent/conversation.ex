defmodule AgenticAiAgent.Conversation do
  @moduledoc """
  Short-term memory for a single chat session. Holds the message window
  and the system prompt; the LLM adapter is *not* called from here — that
  is the orchestrator's job (`AgenticAiAgent.Chat`).

  This is intentionally a process so that:
    * a LiveView can link to it and have its lifecycle bound to the page,
    * later phases (ReAct loop, sub-agents) can keep their own conversation
      stream without interleaving with the parent's.

  Messages follow the OpenAI shape (see `AgenticAiAgent.LLM.Adapter` docs).
  """

  use GenServer

  @type message :: map()

  defmodule State do
    @moduledoc false
    defstruct system_prompt: nil,
              messages: [],
              max_messages: 50
  end

  # ----- Client API -----

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @spec set_system(GenServer.server(), String.t() | nil) :: :ok
  def set_system(pid, prompt), do: GenServer.call(pid, {:set_system, prompt})

  @spec append_user(GenServer.server(), String.t()) :: :ok
  def append_user(pid, content), do: GenServer.call(pid, {:append, "user", content})

  @spec append_assistant(GenServer.server(), String.t()) :: :ok
  def append_assistant(pid, content), do: GenServer.call(pid, {:append, "assistant", content})

  @spec append_message(GenServer.server(), message()) :: :ok
  def append_message(pid, %{"role" => _} = msg), do: GenServer.call(pid, {:append_raw, msg})

  @doc """
  Returns the messages list ready for an LLM call: system message
  prepended (if set) followed by the conversation in order.
  """
  @spec for_llm(GenServer.server()) :: [message()]
  def for_llm(pid), do: GenServer.call(pid, :for_llm)

  @doc "Returns just the user/assistant turn list (no system message) for rendering."
  @spec turns(GenServer.server()) :: [message()]
  def turns(pid), do: GenServer.call(pid, :turns)

  @spec reset(GenServer.server()) :: :ok
  def reset(pid), do: GenServer.call(pid, :reset)

  # ----- Server -----

  @impl true
  def init(opts) do
    {:ok,
     %State{
       system_prompt: Keyword.get(opts, :system_prompt),
       max_messages: Keyword.get(opts, :max_messages, 50)
     }}
  end

  @impl true
  def handle_call({:set_system, prompt}, _from, state),
    do: {:reply, :ok, %{state | system_prompt: prompt}}

  def handle_call({:append, role, content}, _from, state) do
    msg = %{"role" => role, "content" => content}
    {:reply, :ok, %{state | messages: trim(state.messages ++ [msg], state.max_messages)}}
  end

  def handle_call({:append_raw, msg}, _from, state),
    do: {:reply, :ok, %{state | messages: trim(state.messages ++ [msg], state.max_messages)}}

  def handle_call(:for_llm, _from, state) do
    messages =
      case state.system_prompt do
        nil -> state.messages
        text -> [%{"role" => "system", "content" => text} | state.messages]
      end

    {:reply, messages, state}
  end

  def handle_call(:turns, _from, state), do: {:reply, state.messages, state}

  def handle_call(:reset, _from, state),
    do: {:reply, :ok, %{state | messages: []}}

  defp trim(messages, max) when length(messages) > max,
    do: messages |> Enum.reverse() |> Enum.take(max) |> Enum.reverse()

  defp trim(messages, _max), do: messages
end
