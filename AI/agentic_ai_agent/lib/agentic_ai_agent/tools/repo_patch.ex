defmodule AgenticAiAgent.Tools.RepoPatch do
  @moduledoc """
  Apply a unified git patch to the host repository, then run a required
  verification command. This is intentionally critical-risk: it can modify
  source files and execute local test commands.
  """

  @behaviour AgenticAiAgent.Tool

  @max_output 8_000

  @impl true
  def name, do: "repo_patch"

  @impl true
  def description do
    "Apply a unified git patch to the application repository and run a required verification command. If verification fails, the tool attempts to reverse the patch. Critical risk; must be human-approved."
  end

  @impl true
  def input_schema do
    %{
      "type" => "object",
      "required" => ["unified_diff", "test_command", "rationale", "rollback_plan"],
      "properties" => %{
        "unified_diff" => %{
          "type" => "string",
          "minLength" => 1,
          "maxLength" => 200_000,
          "description" => "A git-compatible unified diff to apply."
        },
        "test_command" => %{
          "type" => "object",
          "required" => ["cmd", "args"],
          "properties" => %{
            "cmd" => %{
              "type" => "string",
              "minLength" => 1,
              "maxLength" => 200,
              "description" => "Executable to run without a shell, for example mix."
            },
            "args" => %{
              "type" => "array",
              "items" => %{"type" => "string", "maxLength" => 500},
              "maxItems" => 30
            },
            "env" => %{
              "type" => "object",
              "additionalProperties" => %{"type" => "string", "maxLength" => 1000}
            }
          }
        },
        "expected_test_exit_status" => %{"type" => "integer", "minimum" => 0, "maximum" => 255},
        "rationale" => %{"type" => "string", "minLength" => 20, "maxLength" => 4000},
        "rollback_plan" => %{"type" => "string", "minLength" => 20, "maxLength" => 4000},
        "allow_dirty_worktree" => %{
          "type" => "boolean",
          "description" => "Defaults to false. Keep false for normal operation."
        },
        "dry_run" => %{
          "type" => "boolean",
          "description" => "If true, only checks that the patch applies cleanly."
        }
      }
    }
  end

  @impl true
  def output_schema do
    %{
      "type" => "object",
      "required" => ["applied", "test_exit_status"],
      "properties" => %{
        "applied" => %{"type" => "boolean"},
        "dry_run" => %{"type" => "boolean"},
        "repo_root" => %{"type" => "string"},
        "changed_files" => %{"type" => "array", "items" => %{"type" => "string"}},
        "test_exit_status" => %{"type" => "integer"},
        "test_output" => %{"type" => "string"},
        "reverted" => %{"type" => "boolean"},
        "rollback_plan" => %{"type" => "string"}
      }
    }
  end

  @impl true
  def risk_level, do: :critical

  @impl true
  def side_effects do
    [
      "Modifies files in the host repository.",
      "Runs a local verification command after applying the patch.",
      "Attempts to reverse the patch if verification fails."
    ]
  end

  @impl true
  def failure_modes, do: ["tool_invalid_input", "tool_crash"]

  @impl true
  def retry_policy, do: %{max_retries: 0}

  @impl true
  def precheck(input) do
    with {:ok, root} <- repo_root(),
         :ok <- ensure_git_repo(root),
         :ok <- ensure_command_shape(input),
         :ok <- maybe_clean_worktree(root, input) do
      :ok
    end
  end

  @impl true
  def call(%{"unified_diff" => diff, "test_command" => test_command} = input) do
    with {:ok, root} <- repo_root(),
         {:ok, patch_path} <- write_patch(diff),
         {:ok, changed_files} <- changed_files(root, patch_path),
         :ok <- git_apply_check(root, patch_path) do
      try do
        if Map.get(input, "dry_run") == true do
          {:ok,
           %{
             "applied" => false,
             "dry_run" => true,
             "repo_root" => root,
             "changed_files" => changed_files,
             "test_exit_status" => 0,
             "test_output" => "Patch applies cleanly. dry_run=true, so no files were changed.",
             "reverted" => false,
             "rollback_plan" => input["rollback_plan"]
           }}
        else
          apply_and_verify(root, patch_path, changed_files, test_command, input)
        end
      after
        File.rm(patch_path)
      end
    end
  end

  def call(_), do: {:error, "missing required repo_patch input"}

  defp apply_and_verify(root, patch_path, changed_files, test_command, input) do
    with :ok <- git_apply(root, patch_path) do
      {test_output, test_status} = run_test(root, test_command)
      expected = Map.get(input, "expected_test_exit_status", 0)

      if test_status == expected do
        {:ok,
         %{
           "applied" => true,
           "dry_run" => false,
           "repo_root" => root,
           "changed_files" => changed_files,
           "test_exit_status" => test_status,
           "test_output" => truncate(test_output),
           "reverted" => false,
           "rollback_plan" => input["rollback_plan"]
         }}
      else
        reverted? = reverse_patch(root, patch_path)

        {:error,
         %{
           "reason" => "verification_failed",
           "test_exit_status" => test_status,
           "expected_test_exit_status" => expected,
           "test_output" => truncate(test_output),
           "reverted" => reverted?,
           "rollback_plan" => input["rollback_plan"]
         }}
      end
    end
  end

  defp repo_root do
    root = System.get_env("AGENTIC_REPO_ROOT") || File.cwd!()
    {:ok, Path.expand(root)}
  end

  defp ensure_git_repo(root) do
    case System.cmd("git", ["rev-parse", "--is-inside-work-tree"],
           cd: root,
           stderr_to_stdout: true
         ) do
      {"true\n", 0} ->
        :ok

      {out, status} ->
        {:error,
         "repo_patch requires AGENTIC_REPO_ROOT or cwd to point inside a git worktree (#{status}): " <>
           truncate(out)}
    end
  rescue
    e -> {:error, "repo_patch could not inspect git worktree: #{Exception.message(e)}"}
  end

  defp ensure_command_shape(%{"test_command" => %{"cmd" => cmd, "args" => args}})
       when is_binary(cmd) and is_list(args) do
    cond do
      String.contains?(cmd, <<0>>) ->
        {:error, "test_command.cmd contains a NUL byte"}

      Enum.any?(args, &(not is_binary(&1) or String.contains?(&1, <<0>>))) ->
        {:error, "test_command.args must be strings without NUL bytes"}

      true ->
        :ok
    end
  end

  defp ensure_command_shape(_), do: {:error, "test_command requires cmd and args"}

  defp maybe_clean_worktree(root, input) do
    if Map.get(input, "allow_dirty_worktree") == true do
      :ok
    else
      case System.cmd("git", ["status", "--porcelain"], cd: root, stderr_to_stdout: true) do
        {"", 0} -> :ok
        {out, 0} -> {:error, "refusing dirty worktree before repo_patch:\n" <> truncate(out)}
        {out, status} -> {:error, "git status failed (#{status}): " <> truncate(out)}
      end
    end
  end

  defp write_patch(diff) do
    path =
      Path.join(
        System.tmp_dir!(),
        "agentic-repo-patch-#{System.unique_integer([:positive])}.patch"
      )

    case File.write(path, diff) do
      :ok -> {:ok, path}
      {:error, reason} -> {:error, "could not write patch: #{inspect(reason)}"}
    end
  end

  defp changed_files(root, patch_path) do
    case System.cmd("git", apply_args(root, ["--numstat"], patch_path),
           cd: root,
           stderr_to_stdout: true
         ) do
      {out, 0} ->
        files =
          out
          |> String.split("\n", trim: true)
          |> Enum.map(fn line -> line |> String.split("\t") |> List.last() end)
          |> Enum.reject(&is_nil/1)

        {:ok, files}

      {out, status} ->
        {:error, "git apply --numstat failed (#{status}): " <> truncate(out)}
    end
  end

  defp git_apply_check(root, patch_path) do
    case System.cmd("git", apply_args(root, ["--check"], patch_path),
           cd: root,
           stderr_to_stdout: true
         ) do
      {_out, 0} -> :ok
      {out, status} -> {:error, "git apply --check failed (#{status}): " <> truncate(out)}
    end
  end

  defp git_apply(root, patch_path) do
    case System.cmd("git", apply_args(root, [], patch_path), cd: root, stderr_to_stdout: true) do
      {_out, 0} -> :ok
      {out, status} -> {:error, "git apply failed (#{status}): " <> truncate(out)}
    end
  end

  defp reverse_patch(root, patch_path) do
    case System.cmd("git", apply_args(root, ["-R"], patch_path), cd: root, stderr_to_stdout: true) do
      {_out, 0} -> true
      {_out, _status} -> false
    end
  end

  defp apply_args(root, options, patch_path) do
    ["apply"] ++ apply_directory_option(root) ++ options ++ [patch_path]
  end

  defp apply_directory_option(root) do
    case System.cmd("git", ["rev-parse", "--show-toplevel"], cd: root, stderr_to_stdout: true) do
      {top_level, 0} ->
        {:ok, root} = physical_path(root)
        {:ok, top_level} = physical_path(String.trim(top_level))
        relative = Path.relative_to(root, top_level)

        if relative == "." do
          []
        else
          ["--directory=#{relative}"]
        end

      {_out, _status} ->
        []
    end
  end

  defp physical_path(path) do
    case System.cmd("pwd", ["-P"], cd: path, stderr_to_stdout: true) do
      {out, 0} -> {:ok, String.trim(out)}
      {_out, _status} -> {:ok, Path.expand(path)}
    end
  end

  defp run_test(root, %{"cmd" => cmd, "args" => args} = command) do
    env =
      command
      |> Map.get("env", %{})
      |> Enum.map(fn {k, v} -> {to_string(k), to_string(v)} end)

    System.cmd(cmd, args, cd: root, env: env, stderr_to_stdout: true)
  rescue
    e -> {"test command crashed: #{Exception.message(e)}", 255}
  end

  defp truncate(text) when is_binary(text) do
    if String.length(text) > @max_output,
      do: String.slice(text, 0, @max_output) <> "...",
      else: text
  end

  defp truncate(other), do: other |> inspect() |> truncate()
end
