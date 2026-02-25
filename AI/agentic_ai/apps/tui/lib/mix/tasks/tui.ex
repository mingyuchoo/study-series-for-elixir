defmodule Mix.Tasks.Tui do
  @moduledoc """
  TUI 애플리케이션을 실행합니다.

  ## 사용법

      mix tui

  또는 프로젝트 루트에서:

      ./tui.sh

  """

  use Mix.Task

  @shortdoc "Agentic AI TUI 실행"

  @impl Mix.Task
  def run(_args) do
    # 모든 앱 시작
    Mix.Task.run("app.start")

    # TUI 실행
    TUI.run()
  end
end
