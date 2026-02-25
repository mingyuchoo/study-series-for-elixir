defmodule Auth.GuardianErrorHandler do
  import Plug.Conn

  @behaviour Guardian.Plug.ErrorHandler

  @impl Guardian.Plug.ErrorHandler
  def auth_error(conn, {type, reason}, _opts) do
    # type과 reason을 안전하게 문자열로 변환
    error_type = safe_to_string(type)
    error_reason = safe_to_string(reason)

    body = %{error: error_type, reason: error_reason}

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, Jason.encode!(body))
  end

  # 값을 안전하게 문자열로 변환
  # 에러 구조체나 복잡한 타입도 처리 가능
  defp safe_to_string(value) when is_binary(value), do: value
  defp safe_to_string(value) when is_atom(value), do: to_string(value)
  defp safe_to_string(%{__struct__: _} = struct), do: inspect(struct)
  defp safe_to_string(value), do: inspect(value)
end
