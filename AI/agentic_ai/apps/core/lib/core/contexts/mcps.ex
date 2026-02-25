defmodule Core.Contexts.Mcps do
  @moduledoc """
  MCP(Model Context Protocol) 서버 설정을 관리하는 Context 레이어입니다.

  프로젝트 루트의 `.mcp.json` 파일에서 MCP 서버 설정을 읽어옵니다.
  """

  @mcp_config_filename ".mcp.json"

  @doc """
  설정된 모든 MCP 서버 목록을 반환합니다.

  각 MCP 서버는 다음 정보를 포함합니다:
    - `name`: 서버 이름 (mcpServers의 키)
    - `command`: 실행 명령어
    - `args`: 명령어 인자 목록
    - `env`: 환경 변수 맵

  ## Examples

      iex> list_mcps()
      [
        %{
          name: "firecrawl",
          command: "npx",
          args: ["-y", "firecrawl-mcp"],
          env: %{"FIRECRAWL_API_KEY" => "${FIRECRAWL_API_KEY}"}
        }
      ]

      iex> list_mcps()  # 파일이 없는 경우
      []
  """
  def list_mcps do
    case read_mcp_config() do
      {:ok, config} ->
        config
        |> Map.get("mcpServers", %{})
        |> Enum.map(fn {name, server_config} ->
          %{
            name: name,
            command: Map.get(server_config, "command", ""),
            args: Map.get(server_config, "args", []),
            env: Map.get(server_config, "env", %{})
          }
        end)
        |> Enum.sort_by(& &1.name)

      {:error, _reason} ->
        []
    end
  end

  @doc """
  특정 MCP 서버의 설정을 반환합니다.

  ## Examples

      iex> get_mcp("firecrawl")
      {:ok, %{name: "firecrawl", command: "npx", ...}}

      iex> get_mcp("unknown")
      {:error, :not_found}
  """
  def get_mcp(name) do
    case list_mcps() do
      mcps when is_list(mcps) ->
        case Enum.find(mcps, &(&1.name == name)) do
          nil -> {:error, :not_found}
          mcp -> {:ok, mcp}
        end
    end
  end

  @doc """
  MCP 설정 파일이 존재하는지 확인합니다.

  ## Examples

      iex> config_exists?()
      true
  """
  def config_exists? do
    mcp_config_path()
    |> File.exists?()
  end

  @doc """
  MCP 서버 수를 반환합니다.

  ## Examples

      iex> count_mcps()
      1
  """
  def count_mcps do
    length(list_mcps())
  end

  @doc """
  MCP 서버의 상태를 확인합니다.

  환경 변수 설정 여부를 기반으로 상태를 판단합니다:
    - `:ready` (초록) - 필요한 모든 환경 변수가 설정됨
    - `:unavailable` (빨강) - 필요한 환경 변수가 설정되지 않음
    - `:unknown` (회색) - 환경 변수 없이 작동 (상태 확인 불가)

  ## Examples

      iex> check_mcp_status(%{name: "firecrawl", env: %{"API_KEY" => "${MY_KEY}"}})
      :unavailable

      iex> check_mcp_status(%{name: "simple", env: %{}})
      :unknown
  """
  def check_mcp_status(%{env: env}) when env == %{} or is_nil(env) do
    :unknown
  end

  def check_mcp_status(%{env: env}) when is_map(env) do
    # 환경 변수 플레이스홀더(${VAR_NAME})에서 실제 변수명 추출 후 확인
    missing_vars =
      env
      |> Enum.filter(fn {_key, value} ->
        case extract_env_var_name(value) do
          nil ->
            # 플레이스홀더가 아닌 경우 (하드코딩된 값) - 설정됨으로 간주
            false

          var_name ->
            # 실제 환경 변수가 설정되어 있는지 확인
            is_nil(System.get_env(var_name)) or System.get_env(var_name) == ""
        end
      end)

    if missing_vars == [] do
      :ready
    else
      :unavailable
    end
  end

  def check_mcp_status(_), do: :unknown

  @doc """
  상태와 함께 MCP 목록을 반환합니다.

  ## Examples

      iex> list_mcps_with_status()
      [%{name: "firecrawl", status: :ready, ...}]
  """
  def list_mcps_with_status do
    list_mcps()
    |> Enum.map(fn mcp ->
      Map.put(mcp, :status, check_mcp_status(mcp))
    end)
  end

  # 환경 변수 플레이스홀더에서 변수명 추출
  # "${VAR_NAME}" -> "VAR_NAME"
  defp extract_env_var_name(value) when is_binary(value) do
    case Regex.run(~r/\$\{([^}]+)\}/, value) do
      [_, var_name] -> var_name
      _ -> nil
    end
  end

  defp extract_env_var_name(_), do: nil

  # 비공개 함수들

  defp read_mcp_config do
    path = mcp_config_path()

    case File.read(path) do
      {:ok, content} ->
        Jason.decode(content)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp mcp_config_path do
    # 프로젝트 루트 경로 찾기
    # umbrella 프로젝트이므로 apps 상위 디렉토리를 찾아야 함
    base_path = find_project_root()
    Path.join(base_path, @mcp_config_filename)
  end

  defp find_project_root do
    # 현재 작업 디렉토리에서 시작하여 .mcp.json 또는 mix.exs가 있는 루트를 찾음
    cwd = File.cwd!()

    # umbrella 프로젝트의 경우 apps 폴더의 상위 디렉토리가 루트
    cond do
      File.exists?(Path.join(cwd, @mcp_config_filename)) ->
        cwd

      File.exists?(Path.join(cwd, "apps")) and File.exists?(Path.join(cwd, "mix.exs")) ->
        cwd

      true ->
        # 상위 디렉토리로 올라가며 찾기
        find_project_root_recursive(cwd)
    end
  end

  defp find_project_root_recursive(path) do
    parent = Path.dirname(path)

    cond do
      parent == path ->
        # 루트에 도달 - 현재 작업 디렉토리 반환
        File.cwd!()

      File.exists?(Path.join(parent, @mcp_config_filename)) ->
        parent

      File.exists?(Path.join(parent, "apps")) and File.exists?(Path.join(parent, "mix.exs")) ->
        parent

      true ->
        find_project_root_recursive(parent)
    end
  end
end
