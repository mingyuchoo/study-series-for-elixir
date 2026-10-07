defmodule Core.Agent.WorkerAgentTest do
  use Core.DataCase, async: false

  alias Core.Agent.{MemoryManager, WorkerAgent}
  alias Core.Schema.AgentTask
  import Core.Fixtures

  setup do
    previous_endpoint = Application.get_env(:core, :azure_openai_endpoint)
    Application.delete_env(:core, :azure_openai_endpoint)

    on_exit(fn ->
      if previous_endpoint == nil do
        Application.delete_env(:core, :azure_openai_endpoint)
      else
        Application.put_env(:core, :azure_openai_endpoint, previous_endpoint)
      end
    end)

    :ok
  end

  for mode <- [:regular, :streaming] do
    @tag mode: mode
    test "#{mode} execution records failures for each request's user without crashing", %{
      mode: mode
    } do
      worker = worker_fixture(%{enabled_tools: []})
      supervisor = supervisor_fixture()
      worker_pid = start_supervised!({WorkerAgent, agent_id: worker.id})

      for user <- [user_fixture(), user_fixture()] do
        conversation = conversation_fixture(user_id: user.id)
        request = "Request from #{user.id}"

        task_attrs = %{
          conversation_id: conversation.id,
          supervisor_id: supervisor.id,
          user_id: user.id,
          user_request: request
        }

        result =
          case mode do
            :regular -> WorkerAgent.execute_task(worker_pid, task_attrs)
            :streaming -> WorkerAgent.execute_task_stream(worker_pid, task_attrs, fn _ -> :ok end)
          end

        assert {:error, {:missing_config, :azure_openai_endpoint}} = result
        assert Process.alive?(worker_pid)
        assert :sys.get_state(worker_pid).current_task == nil

        assert [%{user_id: user_id, conversation_id: conversation_id, value: value}] =
                 MemoryManager.retrieve(worker.id, :learned_pattern, user_id: user.id)

        assert user_id == user.id
        assert conversation_id == conversation.id
        assert value["user_request"] == request
        assert value["success"] == false

        task = Repo.get_by!(AgentTask, conversation_id: conversation.id, worker_id: worker.id)
        assert task.status == :failed
        assert task.completed_at != nil
      end

      assert MemoryManager.retrieve(worker.id, :learned_pattern) == []
    end
  end
end
