defmodule Auth.GuardianErrorHandlerTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn

  alias Auth.GuardianErrorHandler

  describe "auth_error/3" do
    test "인증 에러를 401 상태 코드와 JSON으로 반환한다" do
      conn = conn(:get, "/")
      conn = GuardianErrorHandler.auth_error(conn, {:invalid_token, :token_expired}, [])

      assert conn.status == 401
      assert ["application/json; charset=utf-8"] = get_resp_header(conn, "content-type")

      response = Jason.decode!(conn.resp_body)
      assert response["error"] == "invalid_token"
      assert response["reason"] == "token_expired"
    end

    test "다양한 에러 타입을 처리한다" do
      test_cases = [
        {:unauthenticated, :no_token},
        {:invalid_token, :signature_invalid},
        {:token_expired, :expired},
        {:unauthorized, :insufficient_permission}
      ]

      for {type, reason} <- test_cases do
        conn = conn(:get, "/")
        conn = GuardianErrorHandler.auth_error(conn, {type, reason}, [])

        assert conn.status == 401

        response = Jason.decode!(conn.resp_body)
        assert response["error"] == to_string(type)
        assert response["reason"] == to_string(reason)
      end
    end

    test "문자열 에러 타입도 처리한다" do
      conn = conn(:get, "/")
      conn = GuardianErrorHandler.auth_error(conn, {"string_error", "string_reason"}, [])

      assert conn.status == 401

      response = Jason.decode!(conn.resp_body)
      assert response["error"] == "string_error"
      assert response["reason"] == "string_reason"
    end

    test "응답은 유효한 JSON 형식이다" do
      conn = conn(:get, "/")
      conn = GuardianErrorHandler.auth_error(conn, {:test_error, :test_reason}, [])

      assert conn.status == 401
      assert {:ok, _decoded} = Jason.decode(conn.resp_body)
    end

    test "옵션 파라미터는 무시된다" do
      conn1 = GuardianErrorHandler.auth_error(conn(:get, "/"), {:error, :reason}, [])
      conn2 = GuardianErrorHandler.auth_error(conn(:get, "/"), {:error, :reason}, option: "value")
      conn3 = GuardianErrorHandler.auth_error(conn(:get, "/"), {:error, :reason}, key: "value")

      assert conn1.status == 401
      assert conn2.status == 401
      assert conn3.status == 401
    end

    test "에러 메시지는 구조화되어 있다" do
      conn = conn(:get, "/")
      conn = GuardianErrorHandler.auth_error(conn, {:custom_error, :custom_reason}, [])

      response = Jason.decode!(conn.resp_body)

      # 정확히 2개의 키만 있어야 함
      assert Map.keys(response) |> Enum.sort() == ["error", "reason"]
      assert is_binary(response["error"])
      assert is_binary(response["reason"])
    end
  end

  describe "Guardian.Plug.ErrorHandler behaviour" do
    test "@behaviour Guardian.Plug.ErrorHandler를 구현한다" do
      behaviours = Auth.GuardianErrorHandler.__info__(:attributes)[:behaviour] || []
      assert Guardian.Plug.ErrorHandler in behaviours
    end

    test "auth_error/3 콜백을 구현한다" do
      assert function_exported?(Auth.GuardianErrorHandler, :auth_error, 3)
    end
  end

  describe "보안 고려사항" do
    test "에러 상세 정보가 클라이언트에 노출된다" do
      # 현재 구현은 에러 타입과 이유를 모두 노출함
      # 프로덕션 환경에서는 민감한 정보 노출을 방지하기 위해 수정이 필요할 수 있음
      conn = conn(:get, "/")
      conn = GuardianErrorHandler.auth_error(conn, {:internal_error, :database_failure}, [])

      response = Jason.decode!(conn.resp_body)

      # 현재는 상세 정보가 노출됨을 확인
      assert response["error"] == "internal_error"
      assert response["reason"] == "database_failure"
    end

    test "모든 인증 에러는 401 상태 코드를 반환한다" do
      error_types = [
        {:no_resource, :not_found},
        {:invalid_token, :malformed},
        {:unauthorized, :missing_claim},
        {:forbidden, :insufficient_scope}
      ]

      for {type, reason} <- error_types do
        conn = conn(:get, "/")
        conn = GuardianErrorHandler.auth_error(conn, {type, reason}, [])

        # 모든 에러가 401로 통일됨 (403 forbidden도 401로 반환)
        assert conn.status == 401
      end
    end
  end

  describe "Content-Type 헤더" do
    test "application/json Content-Type을 설정한다" do
      conn = conn(:get, "/")
      conn = GuardianErrorHandler.auth_error(conn, {:error, :reason}, [])

      content_type = get_resp_header(conn, "content-type")
      assert content_type == ["application/json; charset=utf-8"]
    end
  end

  describe "Plug.Conn 통합" do
    test "응답 본문이 설정된다" do
      conn = conn(:get, "/")
      conn = GuardianErrorHandler.auth_error(conn, {:error, :reason}, [])

      assert conn.status == 401
      assert conn.resp_body
      assert is_binary(conn.resp_body)
      assert byte_size(conn.resp_body) > 0
    end
  end

  describe "에러 타입 변환 (safe_to_string)" do
    test "문자열 타입과 이유를 그대로 사용한다" do
      conn = conn(:get, "/")
      conn = GuardianErrorHandler.auth_error(conn, {"string_error", "string_reason"}, [])

      assert conn.status == 401
      response = Jason.decode!(conn.resp_body)
      assert response["error"] == "string_error"
      assert response["reason"] == "string_reason"
    end

    test "아톰 타입과 이유를 문자열로 변환한다" do
      conn = conn(:get, "/")
      conn = GuardianErrorHandler.auth_error(conn, {:atom_error, :atom_reason}, [])

      assert conn.status == 401
      response = Jason.decode!(conn.resp_body)
      assert response["error"] == "atom_error"
      assert response["reason"] == "atom_reason"
    end

    test "구조체 타입을 inspect로 변환한다" do
      error_struct = %RuntimeError{message: "test error"}
      conn = conn(:get, "/")
      conn = GuardianErrorHandler.auth_error(conn, {error_struct, :reason}, [])

      assert conn.status == 401
      response = Jason.decode!(conn.resp_body)
      # 구조체는 inspect로 변환됨
      assert String.contains?(response["error"], "RuntimeError")
      assert response["reason"] == "reason"
    end

    test "구조체 이유를 inspect로 변환한다" do
      error_struct = %ArgumentError{message: "invalid argument"}
      conn = conn(:get, "/")
      conn = GuardianErrorHandler.auth_error(conn, {:error, error_struct}, [])

      assert conn.status == 401
      response = Jason.decode!(conn.resp_body)
      assert response["error"] == "error"
      # 구조체는 inspect로 변환됨
      assert String.contains?(response["reason"], "ArgumentError")
    end

    test "기타 타입을 inspect로 변환한다" do
      conn = conn(:get, "/")
      conn = GuardianErrorHandler.auth_error(conn, {[1, 2, 3], %{key: "value"}}, [])

      assert conn.status == 401
      response = Jason.decode!(conn.resp_body)
      # 리스트와 맵은 inspect로 변환됨
      assert response["error"] == "[1, 2, 3]"
      assert String.contains?(response["reason"], "key")
      assert String.contains?(response["reason"], "value")
    end

    test "혼합된 타입을 처리한다" do
      conn = conn(:get, "/")
      conn = GuardianErrorHandler.auth_error(conn, {:atom_error, "string_reason"}, [])

      assert conn.status == 401
      response = Jason.decode!(conn.resp_body)
      assert response["error"] == "atom_error"
      assert response["reason"] == "string_reason"
    end
  end
end
