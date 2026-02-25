defmodule Core.DataCase do
  @moduledoc """
  데이터베이스 접근이 필요한 테스트를 위한 케이스 템플릿입니다.

  각 테스트는 Sandbox 모드에서 실행되어 트랜잭션이 롤백됩니다.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias Core.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Core.DataCase
    end
  end

  setup tags do
    Core.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  Sandbox 모드를 설정합니다.
  """
  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Core.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end

  @doc """
  에러 메시지를 추출하는 헬퍼 함수입니다.
  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
