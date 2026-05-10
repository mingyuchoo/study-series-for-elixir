defmodule Core.Agent.Tool do
  @moduledoc """
  Agent 도구 모듈이 구현해야 하는 공통 계약입니다.
  """

  @callback definition(String.t()) :: map() | nil
  @callback execute(String.t(), map()) :: {:ok, term()} | {:error, term()}
end
