defmodule TUI do
  @moduledoc """
  Agentic AI TUI 앱 진입점.

  터미널 사용자 인터페이스를 통해 AI 비서와 대화할 수 있습니다.

  ## 사용법

      # IEx에서 실행
      iex> TUI.run()

      # 또는 mix 태스크로 실행
      $ cd apps/tui && mix run -e "TUI.run()"
  """

  alias TUI.CLI

  @doc """
  TUI 앱을 시작합니다.
  """
  def run do
    CLI.start()
  end

  @doc """
  TUI 앱을 지정된 옵션으로 시작합니다.

  ## Options

    - `:conversation_id` - 특정 대화로 시작
  """
  def run(opts) do
    CLI.start(opts)
  end
end
