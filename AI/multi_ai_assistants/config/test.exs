import Config

# 테스트 환경 설정
config :core, Core.Repo,
  database: Path.expand("../apps/core/priv/test.db", __DIR__),
  pool: Ecto.Adapters.SQL.Sandbox

# 테스트 중에는 서버를 실행하지 않음
config :web, WebWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base:
    "test_secret_key_base_must_be_at_least_64_bytes_long_for_security_purposes_here",
  server: false

# 테스트 중에는 경고와 오류만 출력
config :logger, level: :warning

# 더 빠른 테스트 컴파일을 위해 런타임에 플러그 초기화
config :phoenix, :plug_init_mode, :runtime
