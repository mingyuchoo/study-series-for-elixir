defmodule Core.Agent.Tools.CodeExecutor do
  @moduledoc """
  Elixir 코드 스니펫을 실행하는 코드 실행 도구.
  타임아웃이 있는 샌드박스 환경에서 실행됩니다.
  """

  @timeout 5_000

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

  def execute("execute_code", %{"code" => code}) do
    task =
      Task.async(fn ->
        try do
          {result, _binding} = Code.eval_string(code, [], __ENV__)
          {:ok, result}
        rescue
          e -> {:error, Exception.message(e)}
        catch
          kind, reason -> {:error, "#{kind}: #{inspect(reason)}"}
        end
      end)

    case Task.yield(task, @timeout) || Task.shutdown(task) do
      {:ok, {:ok, result}} ->
        {:ok,
         %{
           code: code,
           result: inspect(result, pretty: true, limit: 1000),
           type: type_of(result)
         }}

      {:ok, {:error, error}} ->
        {:error, error}

      nil ->
        {:error, "Code execution timed out (#{@timeout}ms limit)"}
    end
  end

  defp type_of(value) when is_binary(value), do: "string"
  defp type_of(value) when is_integer(value), do: "integer"
  defp type_of(value) when is_float(value), do: "float"
  defp type_of(value) when is_list(value), do: "list"
  defp type_of(value) when is_map(value), do: "map"
  defp type_of(value) when is_tuple(value), do: "tuple"
  defp type_of(value) when is_atom(value), do: "atom"
  defp type_of(value) when is_boolean(value), do: "boolean"
  defp type_of(_), do: "unknown"
end
