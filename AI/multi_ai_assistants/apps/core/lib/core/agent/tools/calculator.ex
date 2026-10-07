defmodule Core.Agent.Tools.Calculator do
  @moduledoc """
  수학 연산을 위한 계산기 도구.
  """

  @behaviour Core.Agent.Tool

  def definition("calculate") do
    %{
      name: "calculate",
      description:
        "Perform mathematical calculations. Supports basic arithmetic, powers, square roots, and common math functions.",
      parameters: %{
        type: "object",
        properties: %{
          expression: %{
            type: "string",
            description:
              "Mathematical expression to evaluate (e.g., '2 + 2', '(10 * 5) / 2', 'sqrt(16)', 'pow(2, 8)')"
          }
        },
        required: ["expression"]
      }
    }
  end

  def definition(_), do: nil

  def execute("calculate", %{"expression" => expression}) do
    case AgentDomain.Calculator.evaluate(expression) do
      {:ok, result} ->
        {:ok,
         %{
           expression: expression,
           result: result
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
