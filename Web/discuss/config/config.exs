import Config

# Discuss 도메인 앱 설정
config :discuss,
  ecto_repos: [Discuss.Repo],
  generators: [timestamp_type: :utc_datetime]

# DiscussWeb 엔드포인트 설정
config :discuss_web, DiscussWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: DiscussWeb.ErrorHTML, json: DiscussWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Discuss.PubSub,
  live_view: [signing_salt: "ZGAkxwtt"]

# Mailer 설정
config :discuss, Discuss.Mailer, adapter: Swoosh.Adapters.Local

# esbuild 설정
config :esbuild,
  version: "0.17.11",
  discuss_web: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../apps/discuss_web/assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# tailwind 설정 — npm 기반 빌드 사용 (DaisyUI 지원)

# Logger 설정
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
