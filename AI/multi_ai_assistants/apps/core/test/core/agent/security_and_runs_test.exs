defmodule Core.Agent.SecurityAndRunsTest do
  use Core.DataCase, async: false

  alias Core.Agent.{MemoryManager, RunStore, ToolPolicy}
  alias Core.Agent.Tools.FileSystem
  alias Core.Schema.AgentRun
  import Core.Fixtures

  test "profiles stay with their owners" do
    alice = user_fixture()
    bob = user_fixture()

    assert {:ok, _} = MemoryManager.save_user_profile(alice.id, %{user_name: "Alice"})
    assert {:ok, %{"user_name" => "Alice"}} = MemoryManager.get_user_profile(alice.id)
    assert {:error, :not_found} = MemoryManager.get_user_profile(bob.id)
  end

  test "agent memories with the same key remain separate for each user" do
    alice = user_fixture()
    bob = user_fixture()
    agent = worker_fixture()

    assert {:ok, _} =
             MemoryManager.store(agent.id, :learned_pattern, "error", %{request: "alice"},
               user_id: alice.id
             )

    assert {:ok, _} =
             MemoryManager.store(agent.id, :learned_pattern, "error", %{request: "bob"},
               user_id: bob.id
             )

    assert [%{value: %{"request" => "alice"}}] =
             MemoryManager.retrieve(agent.id, :learned_pattern, user_id: alice.id)

    assert [%{value: %{"request" => "bob"}}] =
             MemoryManager.retrieve(agent.id, :learned_pattern, user_id: bob.id)
  end

  test "state changing tools are denied and agent allowlists are enforced" do
    assert {:error, :tool_requires_approval} = ToolPolicy.authorize("write_file", [])
    assert {:error, :tool_requires_approval} = ToolPolicy.authorize("execute_code", [])
    assert {:error, :tool_requires_approval} = ToolPolicy.authorize("mcp_filesystem_call", [])

    assert {:error, :tool_not_allowed_for_agent} =
             ToolPolicy.authorize("read_file", allowed_tools: ["calculate"])

    assert :ok = ToolPolicy.authorize("read_file", allowed_tools: ["read_file"])
    assert {:error, :invalid_tool_request} = ToolPolicy.authorize(nil, [])
  end

  test "file reads cannot cross user roots or follow symlinks" do
    alice = user_fixture()
    bob = user_fixture()
    root = Path.join(System.tmp_dir!(), "agent_fs_#{System.unique_integer([:positive])}")
    previous = Application.get_env(:core, :workspace_dir)
    Application.put_env(:core, :workspace_dir, root)

    on_exit(fn ->
      Application.put_env(:core, :workspace_dir, previous)
      File.rm_rf(root)
    end)

    alice_root = Path.join([root, "users", alice.id])
    File.mkdir_p!(alice_root)
    File.write!(Path.join(alice_root, "note.txt"), "private")
    File.ln_s!(alice_root, Path.join(alice_root, "link"))

    assert {:ok, %{content: "private"}} =
             FileSystem.execute("read_file", %{"path" => "note.txt"}, alice.id)

    assert {:error, _} = FileSystem.execute("read_file", %{"path" => "note.txt"}, bob.id)

    assert {:error, :invalid_path} =
             FileSystem.execute("read_file", %{"path" => "../#{alice.id}/note.txt"}, bob.id)

    assert {:error, :invalid_path} =
             FileSystem.execute("read_file", %{"path" => "link/note.txt"}, alice.id)

    assert {:error, :invalid_path} =
             FileSystem.execute("read_file", %{"path" => "/etc/passwd"}, alice.id)

    assert {:error, :invalid_arguments} = FileSystem.execute("read_file", %{}, alice.id)
  end

  test "run ownership, checkpoint, budgets and cancellation" do
    alice = user_fixture()
    bob = user_fixture()
    conversation = conversation_fixture(user_id: alice.id)

    assert {:error, :conversation_not_owned} =
             RunStore.create(conversation.id, bob.id, "Summarize")

    assert {:ok, run} = RunStore.create(conversation.id, alice.id, "Summarize")
    assert nil == RunStore.get_owned(bob.id, run.id)

    assert {:ok, checkpoint} =
             RunStore.checkpoint(run.id, 1, [%{kind: :worker, content: "draft"}])

    assert checkpoint.round == 1
    assert checkpoint.transcript["entries"] != []

    previous = Application.get_env(:core, :max_model_calls_per_run)
    Application.put_env(:core, :max_model_calls_per_run, 1)
    on_exit(fn -> Application.put_env(:core, :max_model_calls_per_run, previous) end)

    assert :ok = RunStore.reserve_model_call(run.id)
    assert {:error, :model_call_budget_exceeded} = RunStore.reserve_model_call(run.id)
    assert :ok = RunStore.reserve_tool_call(run.id)
    assert :ok = RunStore.add_tokens(run.id, %{"total_tokens" => 17})
    assert Repo.get!(AgentRun, run.id).tokens_used == 17
    assert {:error, :not_cancellable} = RunStore.cancel(bob.id, run.id)
    assert {:ok, _} = RunStore.cancel(alice.id, run.id)
    assert RunStore.cancelled?(run.id)
    assert {:error, :run_not_running} = RunStore.checkpoint(run.id, 2, [])
    assert {:error, :run_not_running} = RunStore.finish(run.id, "too late")
  end
end
