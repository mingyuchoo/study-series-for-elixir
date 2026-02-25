defmodule TUI.Application do
  @moduledoc """
  TUI 앱 OTP Application.

  TUI.Chat.Handler GenServer를 시작하여 AI 에이전트와의 통신을 담당합니다.
  Ratatouille 런타임은 TUI.run/0에서 직접 시작됩니다.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # 스트리밍 메시지를 수신하고 Ratatouille에 전달하는 GenServer
      {TUI.Chat.Handler, []}
    ]

    opts = [strategy: :one_for_one, name: TUI.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
