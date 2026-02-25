defmodule Core.MCP.ServerTest do
  use ExUnit.Case, async: false

  alias Core.MCP.Server

  setup do
    # 테스트용 서버 시작 (이미 실행 중이면 재사용)
    case Process.whereis(Server) do
      nil ->
        {:ok, _pid} = Server.start_link()

      _pid ->
        :ok
    end

    :ok
  end

  describe "initialize" do
    test "클라이언트 초기화 요청 처리" do
      request = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "initialize",
        "params" => %{
          "protocolVersion" => "2025-06-18",
          "capabilities" => %{},
          "clientInfo" => %{
            "name" => "test-client",
            "version" => "1.0.0"
          }
        }
      }

      {:ok, response} = Server.handle_request(request)

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 1
      assert response["result"]["protocolVersion"] == "2025-06-18"
      assert response["result"]["serverInfo"]["name"] == "agentic-ai-mcp-server"
      assert response["result"]["capabilities"]["tools"]
      assert response["result"]["capabilities"]["prompts"]
      assert response["result"]["capabilities"]["resources"]
    end
  end

  describe "tools/list" do
    test "도구 목록 반환" do
      request = %{
        "jsonrpc" => "2.0",
        "id" => 2,
        "method" => "tools/list"
      }

      {:ok, response} = Server.handle_request(request)

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 2
      assert is_list(response["result"]["tools"])

      # 기본 도구들이 포함되어 있는지 확인
      tool_names = Enum.map(response["result"]["tools"], & &1["name"])
      assert "calculate" in tool_names
      assert "get_current_time" in tool_names
    end
  end

  describe "tools/call" do
    test "calculate 도구 실행" do
      request = %{
        "jsonrpc" => "2.0",
        "id" => 3,
        "method" => "tools/call",
        "params" => %{
          "name" => "calculate",
          "arguments" => %{
            "expression" => "2 + 3 * 4"
          }
        }
      }

      {:ok, response} = Server.handle_request(request)

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 3
      assert is_list(response["result"]["content"])

      [content | _] = response["result"]["content"]
      assert content["type"] == "text"
      assert content["text"] =~ "14"
    end

    test "존재하지 않는 도구 호출 시 에러" do
      request = %{
        "jsonrpc" => "2.0",
        "id" => 4,
        "method" => "tools/call",
        "params" => %{
          "name" => "nonexistent_tool",
          "arguments" => %{}
        }
      }

      {:ok, response} = Server.handle_request(request)

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 4
      assert response["error"]["code"] == -32602
      assert response["error"]["message"] =~ "Tool not found"
    end
  end

  describe "prompts/list" do
    test "프롬프트(스킬) 목록 반환" do
      request = %{
        "jsonrpc" => "2.0",
        "id" => 5,
        "method" => "prompts/list"
      }

      {:ok, response} = Server.handle_request(request)

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 5
      assert is_list(response["result"]["prompts"])
    end
  end

  describe "prompts/get" do
    test "존재하지 않는 프롬프트 조회 시 에러" do
      request = %{
        "jsonrpc" => "2.0",
        "id" => 6,
        "method" => "prompts/get",
        "params" => %{
          "name" => "nonexistent-prompt"
        }
      }

      {:ok, response} = Server.handle_request(request)

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 6
      assert response["error"]["code"] == -32602
    end
  end

  describe "resources/list" do
    test "리소스 목록 반환" do
      request = %{
        "jsonrpc" => "2.0",
        "id" => 7,
        "method" => "resources/list"
      }

      {:ok, response} = Server.handle_request(request)

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 7
      assert is_list(response["result"]["resources"])

      # 메타 리소스가 포함되어 있는지 확인
      uris = Enum.map(response["result"]["resources"], & &1["uri"])
      assert "config://agents" in uris
      assert "config://skills" in uris
    end
  end

  describe "resources/read" do
    test "config://agents 리소스 읽기" do
      request = %{
        "jsonrpc" => "2.0",
        "id" => 8,
        "method" => "resources/read",
        "params" => %{
          "uri" => "config://agents"
        }
      }

      {:ok, response} = Server.handle_request(request)

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 8
      assert is_list(response["result"]["contents"])

      [content | _] = response["result"]["contents"]
      assert content["uri"] == "config://agents"
      assert content["mimeType"] == "application/json"
    end

    test "존재하지 않는 리소스 읽기 시 에러" do
      request = %{
        "jsonrpc" => "2.0",
        "id" => 9,
        "method" => "resources/read",
        "params" => %{
          "uri" => "unknown://resource"
        }
      }

      {:ok, response} = Server.handle_request(request)

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 9
      assert response["error"]["code"] == -32602
    end
  end

  describe "unknown method" do
    test "알 수 없는 메서드 호출 시 에러" do
      request = %{
        "jsonrpc" => "2.0",
        "id" => 10,
        "method" => "unknown/method"
      }

      {:ok, response} = Server.handle_request(request)

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 10
      assert response["error"]["code"] == -32601
      assert response["error"]["message"] == "Method not found"
    end
  end
end
