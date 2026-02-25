defmodule WebWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :web

  # 세션은 쿠키에 저장되고 서명됩니다.
  # 이는 내용을 읽을 수는 있지만 변조할 수 없음을 의미합니다.
  # 암호화도 원하면 :encryption_salt를 설정하세요.
  @session_options [
    store: :cookie,
    key: "_web_key",
    signing_salt: "Z7L/ExYd",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]

  # "priv/static" 디렉토리의 정적 파일을 "/"에서 제공합니다.
  #
  # 코드 리로딩이 비활성화되면 (예: 프로덕션 환경),
  # `gzip` 옵션이 활성화되어 `phx.digest` 실행으로 생성된
  # 압축된 정적 파일을 제공합니다.
  plug Plug.Static,
    at: "/",
    from: :web,
    gzip: not code_reloading?,
    only: WebWeb.static_paths(),
    raise_on_missing_only: code_reloading?

  # 코드 리로딩은 엔드포인트의 :code_reloader 설정에서
  # 명시적으로 활성화할 수 있습니다.
  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug WebWeb.Router
end
