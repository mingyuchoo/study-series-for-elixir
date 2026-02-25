defmodule Core.Agent.Tools.FileSystem do
  @moduledoc """
  파일 읽기, 쓰기, 목록 조회를 위한 파일 시스템 도구.
  안전한 작업 디렉토리로 제한됩니다.
  """

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

  def execute("read_file", %{"path" => path}) do
    full_path = safe_path(path)

    case File.read(full_path) do
      {:ok, content} ->
        {:ok, %{path: path, content: content, size: byte_size(content)}}

      {:error, :enoent} ->
        {:error, "File not found: #{path}"}

      {:error, reason} ->
        {:error, "Failed to read file: #{inspect(reason)}"}
    end
  end

  def execute("write_file", %{"path" => path, "content" => content}) do
    full_path = safe_path(path)

    # 디렉토리 존재 확인
    full_path |> Path.dirname() |> File.mkdir_p!()

    case File.write(full_path, content) do
      :ok ->
        {:ok, %{path: path, written_bytes: byte_size(content)}}

      {:error, reason} ->
        {:error, "Failed to write file: #{inspect(reason)}"}
    end
  end

  def execute("list_directory", %{"path" => path}) do
    full_path = safe_path(path)

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

  defp safe_path(path) do
    # 경로 탐색 공격 방지
    clean_path =
      path
      |> Path.expand()
      |> String.replace(~r/\.\./, "")

    workspace = Application.get_env(:core, :workspace_dir, @workspace_dir)
    File.mkdir_p!(workspace)

    Path.join(workspace, clean_path)
  end

  defp file_size(path) do
    case File.stat(path) do
      {:ok, %{size: size}} -> size
      _ -> nil
    end
  end
end
