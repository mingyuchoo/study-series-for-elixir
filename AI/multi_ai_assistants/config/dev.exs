import Config

# Core 개발 환경 설정
config :core, Core.Repo,
  stacktrace: true,
  show_sensitive_data_on_connection_error: true

# Web 개발 환경 설정
config :web, WebWeb.Endpoint,
  # 브라우저 새로고침/탭 닫기 등으로 연결이 중단될 때 Bandit/ThousandIsland 가
  # :econnaborted GenServer terminating 로그를 매번 남기는 것을 억제합니다.
  http: [
    ip: {127, 0, 0, 1},
    port: 4000,
    thousand_island_options: [silent_terminate_on_error: true]
  ],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base:
    "dev_secret_key_base_must_be_at_least_64_bytes_long_for_security_purposes_here",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:web, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:web, ~w(--watch)]}
  ]

# 대시보드 및 메일박스용 개발 라우트 활성화
config :web, dev_routes: true

# 개발 로그에 메타데이터와 타임스탬프 미포함
config :logger, :console, format: "[$level] $message\n"

# 개발 환경에서 더 긴 스택트레이스 설정
config :phoenix, :stacktrace_depth, 20

# 더 빠른 개발 컴파일을 위해 런타임에 플러그 초기화
config :phoenix, :plug_init_mode, :runtime
