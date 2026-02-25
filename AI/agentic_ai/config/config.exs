# 이 파일은 umbrella 프로젝트와 **모든 애플리케이션** 및
# 해당 의존성을 설정하는 역할을 합니다.
# Azure OpenAI API 접근 권한을 포함합니다.
import Config

# Core 앱 설정
config :core,
  ecto_repos: [Core.Repo]

config :core, Core.Repo,
  database: Path.expand("../apps/core/priv/agentic_ai.db", __DIR__),
  pool_size: 5,
  show_sensitive_data_on_connection_error: true

# Azure OpenAI 설정
config :core,
  azure_openai_endpoint: System.get_env("AZURE_OPENAI_ENDPOINT"),
  azure_openai_api_key: System.get_env("AZURE_OPENAI_API_KEY"),
  azure_openai_api_version: System.get_env("AZURE_OPENAI_API_VERSION", "2024-12-01-preview"),
  workspace_dir: Path.expand("../workspace", __DIR__)

# Web 앱 설정
config :web,
  generators: [context_app: :core]

config :web, WebWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: WebWeb.ErrorHTML, json: WebWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Web.PubSub,
  live_view: [signing_salt: "agentic_ai_secret"]

# 로거 설정
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# JSON 라이브러리
config :phoenix, :json_library, Jason

# esbuild 설정 (버전 필수)
config :esbuild,
  version: "0.25.0",
  web: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../apps/web/assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# tailwind 설정 (버전 필수)
config :tailwind,
  version: "3.4.17",
  web: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/css/app.css
    ),
    cd: Path.expand("../apps/web/assets", __DIR__)
  ]

# 환경별 설정 파일 import
import_config "#{config_env()}.exs"
