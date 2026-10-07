defmodule Core.Agent.Tools.FileSystem do
  @moduledoc """
  파일 읽기, 쓰기, 목록 조회를 위한 파일 시스템 도구.
  안전한 작업 디렉토리로 제한됩니다.
  """

  @behaviour Core.Agent.Tool

  @workspace_dir Application.compile_env(:core, :workspace_dir, "/tmp/agentic_workspace")

  def definition("read_file") do
    %{
      name: "read_file",
      description: "Read the contents of a file in the workspace.",
      parameters: %{
        type: "object",
        properties: %{
          path: %{
            type: "string",
            description: "Relative path to the file within the workspace"
          }
        },
        required: ["path"]
      }
    }
  end

  def definition("write_file") do
    %{
      name: "write_file",
      description:
        "Write content to a file in the workspace. Creates the file if it doesn't exist.",
      parameters: %{
        type: "object",
        properties: %{
          path: %{
            type: "string",
            description: "Relative path to the file within the workspace"
          },
          content: %{
            type: "string",
            description: "Content to write to the file"
          }
        },
        required: ["path", "content"]
      }
    }
  end

  def definition("list_directory") do
    %{
      name: "list_directory",
      description: "List files and directories in a workspace path.",
      parameters: %{
        type: "object",
        properties: %{
          path: %{
            type: "string",
            description: "Relative path to the directory within the workspace. Use '.' for root."
          }
        },
        required: ["path"]
      }
    }
  end

  def definition(_), do: nil

  def execute("read_file", %{"path" => path}, user_id) do
    with {:ok, full_path} <- safe_path(path, user_id) do
      case File.read(full_path) do
        {:ok, content} ->
          {:ok, %{path: path, content: content, size: byte_size(content)}}

        {:error, :enoent} ->
          {:error, "File not found: #{path}"}

        {:error, reason} ->
          {:error, "Failed to read file: #{inspect(reason)}"}
      end
    end
  end

  def execute("write_file", %{"path" => path, "content" => content}, user_id) do
    with {:ok, full_path} <- safe_path(path, user_id),
         :ok <- File.mkdir_p(Path.dirname(full_path)),
         {:ok, ^full_path} <- safe_path(path, user_id) do
      case File.write(full_path, content) do
        :ok ->
          {:ok, %{path: path, written_bytes: byte_size(content)}}

        {:error, reason} ->
          {:error, "Failed to write file: #{inspect(reason)}"}
      end
    end
  end

  def execute("list_directory", %{"path" => path}, user_id) do
    with {:ok, full_path} <- safe_path(path, user_id) do
      case File.ls(full_path) do
        {:ok, entries} ->
          files =
            Enum.map(entries, fn entry ->
              entry_path = Path.join(full_path, entry)

              %{
                name: entry,
                type: if(File.dir?(entry_path), do: "directory", else: "file"),
                size: file_size(entry_path)
              }
            end)

          {:ok, %{path: path, entries: files}}

        {:error, :enoent} ->
          {:error, "Directory not found: #{path}"}

        {:error, reason} ->
          {:error, "Failed to list directory: #{inspect(reason)}"}
      end
    end
  end

  def execute(_, _, _), do: {:error, :invalid_arguments}
  def execute(_, _), do: {:error, :user_context_required}

  defp safe_path(path, user_id) when is_binary(path) and is_binary(user_id) do
    workspace =
      Application.get_env(:core, :workspace_dir, @workspace_dir)
      |> Path.expand()
      |> Path.join("users")
      |> Path.join(user_id)

    full_path = Path.expand(path, workspace)

    if Path.type(path) == :relative and
         (full_path == workspace or String.starts_with?(full_path, workspace <> "/")) and
         not symlink_in_path?(workspace, full_path) do
      {:ok, full_path}
    else
      {:error, :invalid_path}
    end
  end

  defp safe_path(_, _), do: {:error, :invalid_path}

  defp symlink_in_path?(workspace, full_path) do
    components = [workspace | Path.split(Path.relative_to(full_path, workspace))]

    Enum.reduce_while(components, workspace, fn
      ^workspace, _ ->
        if symlink?(workspace), do: {:halt, :symlink}, else: {:cont, workspace}

      component, prefix ->
        current = Path.join(prefix, component)
        if symlink?(current), do: {:halt, :symlink}, else: {:cont, current}
    end) == :symlink
  end

  defp symlink?(path), do: match?({:ok, %{type: :symlink}}, File.lstat(path))

  defp file_size(path) do
    case File.stat(path) do
      {:ok, %{size: size}} -> size
      _ -> nil
    end
  end
end
