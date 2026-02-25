defmodule Core.MCP.Server do
  @moduledoc """
  Model Context Protocol (MCP) 서버 구현.

  MCP 명세(https://modelcontextprotocol.io)에 따른 JSON-RPC 2.0 기반 서버입니다.
  AI 애플리케이션이 도구(Tools), 리소스(Resources), 프롬프트(Prompts)에
  표준화된 방식으로 접근할 수 있도록 합니다.

  ## 지원 기능

  - **Tools**: 에이전트가 실행할 수 있는 도구 (ToolRegistry 연동)
  - **Prompts**: 재사용 가능한 워크플로우 템플릿 (SkillRegistry 연동)
  - **Resources**: 컨텍스트 데이터 (에이전트 설정)

  ## 사용 예시

      # 서버 시작
      {:ok, pid} = Core.MCP.Server.start_link()

      # JSON-RPC 요청 처리
      request = %{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"}
      {:ok, response} = Core.MCP.Server.handle_request(request)
  """

  use GenServer
  require Logger

  alias Core.MCP.{Protocol, Tools, Prompts, Resources}

  @protocol_version "2025-06-18"
  @server_name "agentic-ai-mcp-server"
  @server_version "1.0.0"

  # 클라이언트 API

  @doc """
  MCP 서버를 시작합니다.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  JSON-RPC 요청을 처리합니다.

  ## Parameters

    - `request` - JSON-RPC 2.0 요청 맵

  ## Returns

    - `{:ok, response}` - 성공 시 응답 맵
    - `{:error, error}` - 에러 시 에러 맵
  """
  def handle_request(request) do
    GenServer.call(__MODULE__, {:handle_request, request})
  end

  @doc """
  서버 상태를 반환합니다.
  """
  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  @doc """
  서버 정보를 반환합니다.
  """
  def server_info do
    %{
      "name" => @server_name,
      "version" => @server_version
    }
  end

  @doc """
  프로토콜 버전을 반환합니다.
  """
  def protocol_version, do: @protocol_version

  # 서버 콜백

  @impl true
  def init(_opts) do
    state = %{
      initialized: false,
      client_info: nil,
      capabilities: build_server_capabilities()
    }

    Logger.info("MCP 서버 시작됨 (프로토콜: #{@protocol_version})")
    {:ok, state}
  end

  @impl true
  def handle_call({:handle_request, request}, _from, state) do
    {response, new_state} = process_request(request, state)
    {:reply, {:ok, response}, new_state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  # 비공개 함수들

  defp process_request(request, state) do
    with {:ok, method} <- get_method(request),
         {:ok, id} <- get_id(request) do
      params = Map.get(request, "params", %{})
      {result, new_state} = dispatch_method(method, params, state)

      response = build_response(id, result)
      {response, new_state}
    else
      {:error, error} ->
        id = Map.get(request, "id")
        {build_error_response(id, error), state}
    end
  end

  defp get_method(%{"method" => method}) when is_binary(method), do: {:ok, method}
  defp get_method(_), do: {:error, Protocol.invalid_request_error()}

  defp get_id(%{"id" => id}), do: {:ok, id}
  defp get_id(_), do: {:ok, nil}

  defp dispatch_method(method, params, state) do
    case method do
      # 수명주기 관리
      "initialize" ->
        handle_initialize(params, state)

      "notifications/initialized" ->
        handle_initialized(state)

      # 도구 (Tools)
      "tools/list" ->
        {Tools.list(), state}

      "tools/call" ->
        {Tools.call(params), state}

      # 프롬프트 (Prompts) - Skills 연동
      "prompts/list" ->
        {Prompts.list(), state}

      "prompts/get" ->
        {Prompts.get(params), state}

      # 리소스 (Resources) - 에이전트 설정
      "resources/list" ->
        {Resources.list(), state}

      "resources/read" ->
        {Resources.read(params), state}

      # 알 수 없는 메서드
      _ ->
        {{:error, Protocol.method_not_found_error(method)}, state}
    end
  end

  defp handle_initialize(params, state) do
    client_info = Map.get(params, "clientInfo")
    client_capabilities = Map.get(params, "capabilities", %{})
    _protocol_version = Map.get(params, "protocolVersion", @protocol_version)

    Logger.info("MCP 클라이언트 연결: #{inspect(client_info)}")
    Logger.debug("클라이언트 capabilities: #{inspect(client_capabilities)}")

    result = %{
      "protocolVersion" => @protocol_version,
      "capabilities" => state.capabilities,
      "serverInfo" => server_info()
    }

    new_state = %{state | client_info: client_info}
    {{:ok, result}, new_state}
  end

  defp handle_initialized(state) do
    Logger.info("MCP 초기화 완료")
    new_state = %{state | initialized: true}
    {{:ok, nil}, new_state}
  end

  defp build_server_capabilities do
    %{
      "tools" => %{
        "listChanged" => true
      },
      "prompts" => %{
        "listChanged" => true
      },
      "resources" => %{
        "subscribe" => false,
        "listChanged" => true
      }
    }
  end

  defp build_response(id, {:ok, result}) do
    response = %{
      "jsonrpc" => "2.0",
      "result" => result
    }

    if id, do: Map.put(response, "id", id), else: response
  end

  defp build_response(id, {:error, error}) do
    build_error_response(id, error)
  end

  defp build_error_response(id, error) do
    response = %{
      "jsonrpc" => "2.0",
      "error" => error
    }

    if id, do: Map.put(response, "id", id), else: response
  end
end
