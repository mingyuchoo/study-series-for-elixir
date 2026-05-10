import Config

# 프로덕션 환경 설정
config :web, WebWeb.Endpoint, cache_static_manifest: "priv/static/cache_manifest.json"

# 프로덕션에서 디버그 메시지 출력 안 함
config :logger, level: :info

# 런타임 프로덕션 설정
config :web, WebWeb.Endpoint, server: true
