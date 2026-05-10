import Config

app_root = System.get_env("RELEASE_ROOT") || Path.expand("..", __DIR__)
default_workspace_dir = Path.join(app_root, "workspace")

default_prod_database_path =
  if System.get_env("RELEASE_ROOT") do
    Path.join(app_root, "multi_ai_assistants.db")
  else
    Path.join(app_root, "apps/core/priv/multi_ai_assistants_prod.db")
  end

workspace_dir = System.get_env("WORKSPACE_DIR", default_workspace_dir)

config :core,
  workspace_dir: workspace_dir,
  azure_openai_endpoint: System.get_env("AZURE_OPENAI_ENDPOINT"),
  azure_openai_api_key: System.get_env("AZURE_OPENAI_API_KEY"),
  azure_openai_api_version: System.get_env("AZURE_OPENAI_API_VERSION", "2024-12-01-preview"),
  azure_openai_deployment: System.get_env("AZURE_OPENAI_DEPLOYMENT", "gpt-5-mini")

# 프로덕션용 런타임 설정
if config_env() == :prod do
  database_path = System.get_env("DATABASE_PATH", default_prod_database_path)

  config :core, Core.Repo, database: database_path

  host = System.get_env("PHX_HOST", "localhost")
  port = String.to_integer(System.get_env("PORT", "4000"))

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise("SECRET_KEY_BASE environment variable is not set")

  config :web, WebWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base,
    server: true
end
