defmodule AgenticAiAgent.Tools.Calculator do
  @moduledoc """
  Basic arithmetic. Structured inputs so we never eval untrusted strings.
  """

  @behaviour AgenticAiAgent.Tool

  @ops ~w(add sub mul div pow sqrt)

  @impl true
  def name, do: "calculator"

  @impl true
  def description,
    do:
      "Perform a single arithmetic operation. Supports add, sub, mul, div, pow (uses `a` and `b`) and sqrt (uses `a`)."

  @impl true
  def input_schema do
    %{
      "type" => "object",
      "required" => ["op", "a"],
      "properties" => %{
        "op" => %{"type" => "string", "enum" => @ops},
        "a" => %{"type" => "number"},
        "b" => %{"type" => "number"}
      }
    }
  end

  @impl true
  def output_schema do
    %{
      "type" => "object",
      "required" => ["result"],
      "properties" => %{
        "result" => %{"type" => "number"},
        "op" => %{"type" => "string"}
      }
    }
  end

  @impl true
  def risk_level, do: :low

  @impl true
  def side_effects, do: []

  @impl true
  def failure_modes, do: ["tool_invalid_input"]

  @impl true
  def retry_policy, do: %{max_retries: 0}

  @impl true
  def call(%{"op" => "sqrt", "a" => a}) when is_number(a) do
    cond do
      a < 0 -> {:error, "sqrt of negative number is undefined"}
      true -> {:ok, %{"result" => :math.sqrt(a), "op" => "sqrt"}}
    end
  end

  def call(%{"op" => "div", "a" => _a, "b" => 0}),
    do: {:error, "division by zero"}

  def call(%{"op" => "div", "a" => _a, "b" => +0.0}),
    do: {:error, "division by zero"}

  def call(%{"op" => op, "a" => a, "b" => b})
      when op in ~w(add sub mul div pow) and is_number(a) and is_number(b) do
    {:ok, %{"result" => apply_op(op, a, b), "op" => op}}
  end

  def call(_), do: {:error, "missing or invalid operands"}

  defp apply_op("add", a, b), do: a + b
  defp apply_op("sub", a, b), do: a - b
  defp apply_op("mul", a, b), do: a * b
  defp apply_op("div", a, b), do: a / b
  defp apply_op("pow", a, b), do: :math.pow(a, b)
end
