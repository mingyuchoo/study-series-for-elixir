defmodule AgentDomain.Calculator do
  @moduledoc "Pure arithmetic expression evaluator."

  def evaluate(expression) do
    with {:ok, tokens} <- tokenize(expression),
         {:ok, result, []} <- parse_expression(tokens) do
      {:ok, result}
    else
      {:ok, _result, rest} -> {:error, "Unexpected token: #{inspect(List.first(rest))}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp tokenize(expression), do: tokenize(String.trim(expression), [])

  defp tokenize("", acc), do: {:ok, Enum.reverse(acc)}

  defp tokenize(<<" ", rest::binary>>, acc), do: tokenize(rest, acc)
  defp tokenize(<<"\t", rest::binary>>, acc), do: tokenize(rest, acc)
  defp tokenize(<<"\n", rest::binary>>, acc), do: tokenize(rest, acc)

  defp tokenize(<<char, rest::binary>>, acc) when char in ~c"((),+-*/^" do
    tokenize(rest, [<<char>> | acc])
  end

  defp tokenize(<<char, rest::binary>>, acc) when char in ~c"0123456789." do
    {number, rest} = take_while(rest, <<char>>, &(&1 in ~c"0123456789."))

    case parse_number(number) do
      {:ok, value} -> tokenize(rest, [{:number, value} | acc])
      {:error, _reason} = error -> error
    end
  end

  defp tokenize(<<char, rest::binary>>, acc) when char in ~c"abcdefghijklmnopqrstuvwxyz" do
    {name, rest} = take_while(rest, <<char>>, &(&1 in ~c"abcdefghijklmnopqrstuvwxyz_"))
    tokenize(rest, [{:function, name} | acc])
  end

  defp tokenize(<<char, _rest::binary>>, _acc), do: {:error, "Invalid character: #{<<char>>}"}

  defp parse_expression(tokens) do
    with {:ok, left, rest} <- parse_term(tokens) do
      parse_expression_tail(left, rest)
    end
  end

  defp parse_expression_tail(left, ["+" | rest]) do
    with {:ok, right, rest} <- parse_term(rest) do
      parse_expression_tail(left + right, rest)
    end
  end

  defp parse_expression_tail(left, ["-" | rest]) do
    with {:ok, right, rest} <- parse_term(rest) do
      parse_expression_tail(left - right, rest)
    end
  end

  defp parse_expression_tail(left, rest), do: {:ok, left, rest}

  defp parse_term(tokens) do
    with {:ok, left, rest} <- parse_power(tokens) do
      parse_term_tail(left, rest)
    end
  end

  defp parse_term_tail(left, ["*" | rest]) do
    with {:ok, right, rest} <- parse_power(rest) do
      parse_term_tail(left * right, rest)
    end
  end

  defp parse_term_tail(_left, ["/", {:number, 0} | _rest]), do: {:error, "Division by zero"}

  defp parse_term_tail(left, ["/" | rest]) do
    with {:ok, right, rest} <- parse_power(rest) do
      if right == 0 do
        {:error, "Division by zero"}
      else
        parse_term_tail(left / right, rest)
      end
    end
  end

  defp parse_term_tail(left, rest), do: {:ok, left, rest}

  defp parse_power(tokens) do
    case parse_unary(tokens) do
      {:ok, left, ["^" | rest]} -> parse_power_right(left, rest)
      {:ok, left, rest} -> {:ok, left, rest}
      {:error, _reason} = error -> error
    end
  end

  defp parse_power_right(left, rest) do
    with {:ok, right, rest} <- parse_power(rest) do
      {:ok, :math.pow(left, right), rest}
    end
  end

  defp parse_unary(["-" | rest]) do
    with {:ok, value, rest} <- parse_unary(rest) do
      {:ok, -value, rest}
    end
  end

  defp parse_unary(["+" | rest]), do: parse_unary(rest)
  defp parse_unary(tokens), do: parse_primary(tokens)

  defp parse_primary([{:number, value} | rest]), do: {:ok, value, rest}

  defp parse_primary(["(" | rest]) do
    case parse_expression(rest) do
      {:ok, value, [")" | rest]} -> {:ok, value, rest}
      {:ok, _value, _rest} -> {:error, "Missing closing parenthesis"}
      {:error, _reason} = error -> error
    end
  end

  defp parse_primary([{:function, name}, "(" | rest]) do
    with {:ok, args, rest} <- parse_function_args(rest),
         {:ok, value} <- apply_function(name, args) do
      {:ok, value, rest}
    end
  end

  defp parse_primary([token | _rest]), do: {:error, "Unexpected token: #{inspect(token)}"}
  defp parse_primary([]), do: {:error, "Unexpected end of expression"}

  defp parse_function_args(tokens) do
    case parse_expression(tokens) do
      {:ok, first, ["," | rest]} -> parse_second_function_arg(first, rest)
      {:ok, first, [")" | rest]} -> {:ok, [first], rest}
      {:ok, _first, _rest} -> {:error, "Missing closing parenthesis"}
      {:error, _reason} = error -> error
    end
  end

  defp parse_second_function_arg(first, rest) do
    case parse_expression(rest) do
      {:ok, second, [")" | rest]} -> {:ok, [first, second], rest}
      {:ok, _second, _rest} -> {:error, "Missing closing parenthesis"}
      {:error, _reason} = error -> error
    end
  end

  defp apply_function("sqrt", [value]), do: {:ok, :math.sqrt(value)}
  defp apply_function("sin", [value]), do: {:ok, :math.sin(value)}
  defp apply_function("cos", [value]), do: {:ok, :math.cos(value)}
  defp apply_function("tan", [value]), do: {:ok, :math.tan(value)}
  defp apply_function("log", [value]), do: {:ok, :math.log(value)}
  defp apply_function("abs", [value]), do: {:ok, abs(value)}
  defp apply_function("pow", [base, exponent]), do: {:ok, :math.pow(base, exponent)}
  defp apply_function(name, _args), do: {:error, "Unknown function: #{name}"}

  defp take_while(<<char, rest::binary>>, acc, predicate) when is_function(predicate, 1) do
    if predicate.(char) do
      take_while(rest, acc <> <<char>>, predicate)
    else
      {acc, <<char, rest::binary>>}
    end
  end

  defp take_while("", acc, _predicate), do: {acc, ""}

  defp parse_number(number) do
    parser = if String.contains?(number, "."), do: &Float.parse/1, else: &Integer.parse/1

    case parser.(number) do
      {value, ""} -> {:ok, value}
      _ -> {:error, "Invalid number: #{number}"}
    end
  end
end
