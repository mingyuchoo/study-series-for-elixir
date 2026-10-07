defmodule Core.Agent.Tools.CodeExecutor do
  @moduledoc """
  Elixir 코드 스니펫을 실행하는 코드 실행 도구.
  안전한 외부 실행기가 준비될 때까지 비활성화됩니다.
  """

  @behaviour Core.Agent.Tool

  def definition("execute_code") do
    %{
      name: "execute_code",
      description:
        "Execute Elixir code and return the result. Use for calculations, data transformations, or testing logic.",
      parameters: %{
        type: "object",
        properties: %{
          code: %{
            type: "string",
            description: "Elixir code to execute. Should be a valid Elixir expression."
          }
        },
        required: ["code"]
      }
    }
  end

  def definition(_), do: nil

  def execute("execute_code", _arguments), do: {:error, :code_execution_disabled}
end
