defmodule Core.Contexts.Mcps do
  @moduledoc """
  MCP(Model Context Protocol) 서버를 DB 기반으로 관리하는 Context.
  초기 데이터는 .mcp.json에서 시드됩니다 (seeds.exs 참조).
  """

  import Ecto.Query, warn: false
  alias Core.Repo
  alias Core.Schema.Mcp

  @doc """
  모든 MCP 서버를 이름 순으로 조회합니다.
  """
  def list_mcps do
    from(m in Mcp, order_by: [asc: m.name])
    |> Repo.all()
    |> Enum.map(&to_external/1)
  end

  @doc """
  활성화된 MCP만 조회합니다.
  """
  def list_active_mcps do
    from(m in Mcp, where: m.enabled == true, order_by: [asc: m.name])
    |> Repo.all()
    |> Enum.map(&to_external/1)
  end

  def get_mcp!(id), do: Repo.get!(Mcp, id)

  def get_mcp_by_name(name), do: Repo.get_by(Mcp, name: name)

  def create_mcp(attrs \\ %{}) do
    %Mcp{}
    |> Mcp.changeset(attrs)
    |> Repo.insert()
  end

  def update_mcp(%Mcp{} = mcp, attrs) do
    mcp
    |> Mcp.changeset(attrs)
    |> Repo.update()
  end

  def delete_mcp(%Mcp{} = mcp), do: Repo.delete(mcp)

  def change_mcp(%Mcp{} = mcp, attrs \\ %{}) do
    Mcp.changeset(mcp, attrs)
  end

  def count_mcps, do: Repo.aggregate(Mcp, :count, :id)

  @doc """
  상태와 함께 MCP 목록을 반환합니다 (UI용).
  """
  def list_mcps_with_status do
    list_active_mcps()
    |> Enum.map(fn mcp ->
      Map.put(mcp, :status, check_mcp_status(mcp))
    end)
  end

  @doc """
  환경 변수 설정 여부로 MCP 상태를 판단합니다.
  """
  def check_mcp_status(%{env: env}) when env == %{} or is_nil(env), do: :unknown

  def check_mcp_status(%{env: env}) when is_map(env) do
    missing =
      env
      |> Enum.filter(fn {_key, value} ->
        case extract_env_var_name(value) do
          nil -> false
          var -> is_nil(System.get_env(var)) or System.get_env(var) == ""
        end
      end)

    if missing == [], do: :ready, else: :unavailable
  end

  def check_mcp_status(_), do: :unknown

  defp extract_env_var_name(value) when is_binary(value) do
    case Regex.run(~r/\$\{([^}]+)\}/, value) do
      [_, var] -> var
      _ -> nil
    end
  end

  defp extract_env_var_name(_), do: nil

  # 외부 호출자에게 일관된 형태로 노출 (기존 API 형태 유지)
  defp to_external(%Mcp{} = mcp) do
    %{
      id: mcp.id,
      name: mcp.name,
      command: mcp.command,
      args: mcp.args || [],
      env: mcp.env || %{},
      enabled: mcp.enabled
    }
  end
end
