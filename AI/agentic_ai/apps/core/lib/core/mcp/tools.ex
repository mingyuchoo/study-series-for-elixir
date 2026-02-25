defmodule Core.MCP.Tools do
  @moduledoc """
  MCP Tools 엔드포인트 구현.

  ToolRegistry의 도구들을 MCP 명세에 따라 노출합니다.

  ## MCP Tools 명세

  - `tools/list`: 사용 가능한 모든 도구 목록 반환
  - `tools/call`: 특정 도구 실행

  ## 도구 정의 형식

      %{
        "name" => "calculator_arithmetic",
        "title" => "Calculator",
        "description" => "수학 계산 수행",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{...},
          "required" => [...]
        }
      }
  """

  alias Core.Agent.ToolRegistry
  alias Core.MCP.Protocol

  @doc """
  모든 도구 목록을 반환합니다 (tools/list).

  ## Returns

      {:ok, %{"tools" => [...]}}
  """
  def list do
    tools =
      ToolRegistry.get_tools()
      |> Enum.map(&convert_to_mcp_format/1)

    {:ok, %{"tools" => tools}}
  end

  @doc """
  도구를 실행합니다 (tools/call).

  ## Parameters

    - `params` - 도구 호출 파라미터
      - `"name"` - 도구 이름 (필수)
      - `"arguments"` - 도구 인자 (선택)

  ## Returns

      {:ok, %{"content" => [%{"type" => "text", "text" => "..."}]}}
  """
  def call(%{"name" => name} = params) do
    arguments = Map.get(params, "arguments", %{})

    case ToolRegistry.execute(name, arguments) do
      {:ok, result} ->
        {:ok, format_tool_result(result)}

      {:error, :tool_not_found} ->
        {:error, Protocol.invalid_params_error("Tool not found: #{name}")}

      {:error, reason} ->
        {:ok, format_tool_error(reason)}
    end
  end

  def call(_params) do
    {:error, Protocol.invalid_params_error("Missing required parameter: name")}
  end

  # 비공개 함수들

  defp convert_to_mcp_format(tool_definition) when is_map(tool_definition) do
    # 도구 정의를 MCP 형식으로 변환
    # ToolRegistry는 %{name: ..., description: ..., parameters: ...} 형식 반환
    name = get_tool_name(tool_definition)
    description = get_tool_description(tool_definition)
    parameters = get_tool_parameters(tool_definition)

    %{
      "name" => name,
      "title" => humanize_name(name),
      "description" => description,
      "inputSchema" => parameters
    }
  end

  defp get_tool_name(tool) do
    # atom 키 또는 string 키 모두 지원
    tool[:name] || tool["name"] || tool["function"]["name"] || "unknown"
  end

  defp get_tool_description(tool) do
    tool[:description] || tool["description"] || tool["function"]["description"] || ""
  end

  defp get_tool_parameters(tool) do
    params = tool[:parameters] || tool["parameters"] || tool["function"]["parameters"] || %{}
    # atom 키를 문자열 키로 변환
    stringify_keys(params)
  end

  defp stringify_keys(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} ->
      key = if is_atom(k), do: Atom.to_string(k), else: k
      value = stringify_keys(v)
      {key, value}
    end)
    |> Map.new()
  end

  defp stringify_keys(list) when is_list(list) do
    Enum.map(list, &stringify_keys/1)
  end

  defp stringify_keys(value), do: value

  defp humanize_name(nil), do: "Unknown"

  defp humanize_name(name) when is_atom(name), do: humanize_name(Atom.to_string(name))

  defp humanize_name(name) when is_binary(name) do
    name
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp format_tool_result(result) when is_binary(result) do
    %{
      "content" => [
        %{
          "type" => "text",
          "text" => result
        }
      ]
    }
  end

  defp format_tool_result(result) when is_map(result) do
    text =
      case Jason.encode(result, pretty: true) do
        {:ok, json} -> json
        {:error, _} -> inspect(result)
      end

    %{
      "content" => [
        %{
          "type" => "text",
          "text" => text
        }
      ]
    }
  end

  defp format_tool_result(result) do
    %{
      "content" => [
        %{
          "type" => "text",
          "text" => inspect(result)
        }
      ]
    }
  end

  defp format_tool_error(reason) when is_binary(reason) do
    %{
      "content" => [
        %{
          "type" => "text",
          "text" => "Error: #{reason}"
        }
      ],
      "isError" => true
    }
  end

  defp format_tool_error(reason) do
    %{
      "content" => [
        %{
          "type" => "text",
          "text" => "Error: #{inspect(reason)}"
        }
      ],
      "isError" => true
    }
  end
end
