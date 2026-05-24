defmodule AgenticAiAgent.Agent.RuntimeLifecycleTest do
  use AgenticAiAgent.DataCase, async: false

  alias AgenticAiAgent.Agent.Runtime
  alias AgenticAiAgent.Conversation
  alias AgenticAiAgent.LLM.Response
  alias AgenticAiAgent.Traces

  defmodule StubAdapter do
    @behaviour AgenticAiAgent.LLM.Adapter

    @impl true
    def chat(_messages, _opts) do
      {:ok,
       %Response{
         content: "오늘은 맑습니다.",
         finish_reason: "stop",
         model: "stub-model",
         usage: %{"prompt_tokens" => 1, "completion_tokens" => 1}
       }}
    end
  end

  setup do
    old_adapter = Application.get_env(:agentic_ai_agent, :llm_adapter)
    Application.put_env(:agentic_ai_agent, :llm_adapter, StubAdapter)

    on_exit(fn ->
      if old_adapter do
        Application.put_env(:agentic_ai_agent, :llm_adapter, old_adapter)
      else
        Application.delete_env(:agentic_ai_agent, :llm_adapter)
      end
    end)

    :ok
  end

  test "a run finishes even when the original subscriber process is gone" do
    Phoenix.PubSub.subscribe(AgenticAiAgent.PubSub, Runtime.runs_topic())

    {:ok, conv} = Conversation.start(system_prompt: "Answer briefly.")

    subscriber =
      spawn(fn ->
        :ok
      end)

    ref = Process.monitor(subscriber)
    assert_receive {:DOWN, ^ref, :process, ^subscriber, reason} when reason in [:normal, :noproc]

    assert {:ok, _runtime} =
             Runtime.start(
               conversation: conv,
               user_input: "오늘 날씨 알려줘.",
               subscriber: subscriber,
               max_steps: 2
             )

    assert_receive {:runs, :created, %{id: run_id}}, 500
    assert_receive {:runs, :updated, ^run_id}, 2_000

    run = Traces.get_run!(run_id)
    assert run.status == "done"
    assert run.final_answer == "오늘은 맑습니다."
    assert eventually?(fn -> not Process.alive?(conv) end)
  end

  defp eventually?(fun, attempts \\ 20)

  defp eventually?(fun, attempts) when attempts > 0 do
    if fun.() do
      true
    else
      Process.sleep(25)
      eventually?(fun, attempts - 1)
    end
  end

  defp eventually?(_fun, 0), do: false
end
