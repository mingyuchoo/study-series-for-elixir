defmodule Core.Agent.GroupChatTest do
  use Core.DataCase, async: false

  alias Core.Agent.{GroupChat, RoutingRules, TaskRouter}
  alias Core.Repo
  alias Core.Schema.Message
  import Core.Fixtures
  import Ecto.Query

  defmodule FailingStreamingWorker do
    use GenServer

    def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok)

    @impl true
    def init(state), do: {:ok, state}

    @impl true
    def handle_call({:execute_task_stream, _task_attrs, callback}, _from, state) do
      callback.({:chunk, "오늘 "})
      callback.({:chunk, "날씨를 확인하고 있습니다."})
      {:reply, {:error, :simulated_failure}, state}
    end
  end

  test "worker response streamed before an error remains in the conversation" do
    user = user_fixture()
    conversation = conversation_fixture(user_id: user.id)
    supervisor = supervisor_fixture()

    worker =
      worker_fixture(%{
        name: "research_worker",
        description: "오늘 날씨 알려줘.",
        enabled_tools: ["search_web"]
      })

    {:ok, worker_pid} = FailingStreamingWorker.start_link([])
    RoutingRules.seed_defaults()

    assert {:ok, ^worker, score} =
             TaskRouter.select_worker_with_score("오늘 날씨 알려줘.", [worker])

    assert score >= 35

    previous_endpoint = Application.get_env(:core, :azure_openai_endpoint)
    Application.delete_env(:core, :azure_openai_endpoint)
    on_exit(fn -> Application.put_env(:core, :azure_openai_endpoint, previous_endpoint) end)

    assert {:ok, answer} =
             GroupChat.run(%{
               supervisor: supervisor,
               workers: [{worker, worker_pid}],
               conversation_id: conversation.id,
               user_id: user.id,
               user_request: "오늘 날씨 알려줘.",
               liveview_pid: self(),
               max_rounds: 1
             })

    assert answer =~ "오늘 날씨를 확인하고 있습니다."

    messages =
      Message
      |> where([m], m.conversation_id == ^conversation.id)
      |> order_by([m], asc: m.inserted_at)
      |> Repo.all()

    assert Enum.any?(messages, fn message ->
             message.agent_id == worker.id and message.visibility == :debate_turn and
               message.content =~ "오늘 날씨를 확인하고 있습니다." and
               message.content =~ "응답이 중단되어"
           end)

    assert_receive {:debate_message_inserted, conversation_id, %{agent_id: agent_id}}
                   when conversation_id == conversation.id and agent_id == worker.id
  end
end
