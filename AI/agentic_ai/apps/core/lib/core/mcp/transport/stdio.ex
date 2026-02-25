defmodule Core.MCP.Transport.Stdio do
  @moduledoc """
  MCP STDIO 트랜스포트 구현.

  표준 입출력(stdin/stdout)을 통해 MCP 클라이언트와 통신합니다.
  각 메시지는 줄바꿈으로 구분된 JSON-RPC 2.0 형식입니다.

  ## 사용법

  MCP 서버를 STDIO 모드로 실행:

      mix run --no-halt -e "Core.MCP.Transport.Stdio.start()"

  또는 릴리즈에서:

      ./bin/agentic_ai eval "Core.MCP.Transport.Stdio.start()"
  """

  use GenServer
  require Logger

  alias Core.MCP.{Server, Protocol}

  @doc """
  STDIO 트랜스포트를 시작합니다.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  독립 실행 모드로 STDIO 서버를 시작합니다.
  """
  def start do
    # MCP 서버가 실행 중인지 확인
    case Process.whereis(Server) do
      nil ->
        {:ok, _} = Server.start_link()

      _ ->
        :ok
    end

    # STDIO 트랜스포트 시작
    {:ok, pid} = start_link()

    # 입력 루프 실행
    run_input_loop(pid)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    Logger.info("MCP STDIO 트랜스포트 시작됨")

    state = %{
      running: true
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:process_line, line}, state) do
    case process_input(line) do
      {:ok, response} ->
        output_response(response)

      {:error, error} ->
        output_error(error)

      :notification ->
        # 알림은 응답하지 않음
        :ok
    end

    {:noreply, state}
  end

  @impl true
  def handle_cast(:stop, state) do
    Logger.info("MCP STDIO 트랜스포트 종료됨")
    {:stop, :normal, state}
  end

  # Public Functions

  @doc """
  입력 라인을 처리합니다.
  """
  def process_line(line) do
    GenServer.cast(__MODULE__, {:process_line, line})
  end

  @doc """
  트랜스포트를 종료합니다.
  """
  def stop do
    GenServer.cast(__MODULE__, :stop)
  end

  # Private Functions

  defp run_input_loop(pid) do
    case IO.read(:stdio, :line) do
      :eof ->
        Logger.info("EOF 수신, 종료합니다")
        GenServer.cast(pid, :stop)

      {:error, reason} ->
        Logger.error("입력 읽기 오류: #{inspect(reason)}")
        GenServer.cast(pid, :stop)

      line ->
        line = String.trim(line)

        if line != "" do
          process_line(line)
        end

        run_input_loop(pid)
    end
  end

  defp process_input(line) do
    with {:ok, request} <- Protocol.parse_request(line) do
      # notification인지 확인 (id가 없으면 notification)
      if Map.has_key?(request, "id") do
        Server.handle_request(request)
      else
        # Notification 처리
        handle_notification(request)
        :notification
      end
    end
  end

  defp handle_notification(%{"method" => "notifications/initialized"}) do
    Logger.info("클라이언트 초기화 완료 알림 수신")
    # 상태 업데이트는 Server에서 처리
    Server.handle_request(%{
      "jsonrpc" => "2.0",
      "id" => "internal_init",
      "method" => "notifications/initialized"
    })
  end

  defp handle_notification(%{"method" => method}) do
    Logger.debug("알림 수신: #{method}")
  end

  defp output_response({:ok, response}) do
    case Jason.encode(response) do
      {:ok, json} ->
        IO.puts(:stdio, json)

      {:error, reason} ->
        Logger.error("응답 인코딩 실패: #{inspect(reason)}")
    end
  end

  defp output_response({:error, error}) do
    output_error(error)
  end

  defp output_error(error) do
    response = Protocol.build_error_response(nil, error)

    case Jason.encode(response) do
      {:ok, json} ->
        IO.puts(:stdio, json)

      {:error, reason} ->
        Logger.error("에러 응답 인코딩 실패: #{inspect(reason)}")
    end
  end
end
