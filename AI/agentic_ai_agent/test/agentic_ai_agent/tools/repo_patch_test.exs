defmodule AgenticAiAgent.Tools.RepoPatchTest do
  use AgenticAiAgent.DataCase, async: false

  alias AgenticAiAgent.Tools.Registry

  defp temp_repo!(name) do
    root = Path.join(System.tmp_dir!(), "#{name}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    File.write!(Path.join(root, "README.md"), "old\n")

    {_, 0} = System.cmd("git", ["init"], cd: root, stderr_to_stdout: true)

    root
  end

  defp patch(from, to) do
    """
    diff --git a/README.md b/README.md
    --- a/README.md
    +++ b/README.md
    @@ -1 +1 @@
    -#{from}
    +#{to}
    """
  end

  defp input(diff, status) do
    %{
      "unified_diff" => diff,
      "test_command" => %{"cmd" => "elixir", "args" => ["-e", "System.halt(#{status})"]},
      "rationale" => "Apply a minimal test patch through the critical repo_patch tool.",
      "rollback_plan" => "Reverse the unified diff if verification fails.",
      "allow_dirty_worktree" => true
    }
  end

  setup do
    old_root = System.get_env("AGENTIC_REPO_ROOT")

    on_exit(fn ->
      if old_root,
        do: System.put_env("AGENTIC_REPO_ROOT", old_root),
        else: System.delete_env("AGENTIC_REPO_ROOT")
    end)

    :ok
  end

  test "repo_patch is registered as a critical builtin tool" do
    assert Registry.risk_level("repo_patch") == :critical
    assert Registry.enabled?("repo_patch")
    assert Enum.any?(Registry.descriptors(), &(&1["name"] == "repo_patch"))
  end

  test "applies a patch when verification succeeds" do
    root = temp_repo!("repo-patch-success")
    System.put_env("AGENTIC_REPO_ROOT", root)

    assert {:ok, result} = Registry.call_with_policy("repo_patch", input(patch("old", "new"), 0))
    assert result["applied"] == true
    assert result["test_exit_status"] == 0
    assert File.read!(Path.join(root, "README.md")) == "new\n"
  end

  test "accepts a repository subdirectory as AGENTIC_REPO_ROOT" do
    root = Path.join(System.tmp_dir!(), "repo-patch-subdir-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    {_, 0} = System.cmd("git", ["init"], cd: root, stderr_to_stdout: true)

    app_dir = Path.join(root, "app")
    File.mkdir_p!(app_dir)
    File.write!(Path.join(app_dir, "README.md"), "old\n")
    System.put_env("AGENTIC_REPO_ROOT", app_dir)

    assert {:ok, result} = Registry.call_with_policy("repo_patch", input(patch("old", "new"), 0))
    assert result["applied"] == true
    assert File.read!(Path.join(app_dir, "README.md")) == "new\n"
  end

  test "reverts the patch when verification fails" do
    root = temp_repo!("repo-patch-revert")
    System.put_env("AGENTIC_REPO_ROOT", root)

    assert {:error, result} =
             Registry.call_with_policy("repo_patch", input(patch("old", "new"), 42))

    assert result["reason"] == "verification_failed"
    assert result["test_exit_status"] == 42
    assert result["reverted"] == true
    assert File.read!(Path.join(root, "README.md")) == "old\n"
  end
end
