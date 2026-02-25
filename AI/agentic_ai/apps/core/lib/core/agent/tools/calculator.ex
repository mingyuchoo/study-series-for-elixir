defmodule Core.Agent.Tools.Calculator do
  @moduledoc """
  수학 연산을 위한 계산기 도구.
  """

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
    case evaluate(expression) do
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

  defp evaluate(expression) do
    # 수식 정제 및 파싱
    sanitized =
      expression
      |> String.replace("sqrt", ":math.sqrt")
      |> String.replace("pow", ":math.pow")
      |> String.replace("sin", ":math.sin")
      |> String.replace("cos", ":math.cos")
      |> String.replace("tan", ":math.tan")
      |> String.replace("log", ":math.log")
      |> String.replace("abs", "Kernel.abs")
      |> String.replace("^", "**")

    # 안전한 문자만 허용
    if Regex.match?(~r/^[\d\s\+\-\*\/\(\)\.\,\:\w]+$/, sanitized) do
      try do
        {result, _} = Code.eval_string(sanitized)
        {:ok, result}
      rescue
        e -> {:error, Exception.message(e)}
      end
    else
      {:error, "Invalid expression"}
    end
  end
end
