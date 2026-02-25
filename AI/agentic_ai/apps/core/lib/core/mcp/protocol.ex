defmodule Core.MCP.Protocol do
  @moduledoc """
  MCP JSON-RPC 2.0 프로토콜 헬퍼.

  JSON-RPC 2.0 표준 에러 코드와 메시지 빌더를 제공합니다.
  """

  # JSON-RPC 2.0 표준 에러 코드
  @parse_error -32700
  @invalid_request -32600
  @method_not_found -32601
  @invalid_params -32602
  @internal_error -32603

  @doc """
  JSON 파싱 에러.
  """
  def parse_error do
    %{
      "code" => @parse_error,
      "message" => "Parse error"
    }
  end

  @doc """
  잘못된 요청 에러.
  """
  def invalid_request_error do
    %{
      "code" => @invalid_request,
      "message" => "Invalid Request"
    }
  end

  @doc """
  메서드를 찾을 수 없음 에러.
  """
  def method_not_found_error(method \\ nil) do
    %{
      "code" => @method_not_found,
      "message" => "Method not found",
      "data" => %{"method" => method}
    }
  end

  @doc """
  잘못된 파라미터 에러.
  """
  def invalid_params_error(message \\ "Invalid params") do
    %{
      "code" => @invalid_params,
      "message" => message
    }
  end

  @doc """
  내부 서버 에러.
  """
  def internal_error(details \\ nil) do
    error = %{
      "code" => @internal_error,
      "message" => "Internal error"
    }

    if details, do: Map.put(error, "data", details), else: error
  end

  @doc """
  JSON-RPC 2.0 요청을 파싱합니다.
  """
  def parse_request(json_string) when is_binary(json_string) do
    case Jason.decode(json_string) do
      {:ok, request} -> validate_request(request)
      {:error, _} -> {:error, parse_error()}
    end
  end

  @doc """
  JSON-RPC 2.0 요청을 검증합니다.
  """
  def validate_request(%{"jsonrpc" => "2.0", "method" => method} = request)
      when is_binary(method) do
    {:ok, request}
  end

  def validate_request(_) do
    {:error, invalid_request_error()}
  end

  @doc """
  성공 응답을 빌드합니다.
  """
  def build_success_response(id, result) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => result
    }
  end

  @doc """
  에러 응답을 빌드합니다.
  """
  def build_error_response(id, error) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "error" => error
    }
  end

  @doc """
  알림(notification)을 빌드합니다. (id 없음)
  """
  def build_notification(method, params \\ nil) do
    notification = %{
      "jsonrpc" => "2.0",
      "method" => method
    }

    if params, do: Map.put(notification, "params", params), else: notification
  end

  @doc """
  응답을 JSON 문자열로 인코딩합니다.
  """
  def encode_response(response) do
    Jason.encode(response)
  end
end
