import Config

# 프로덕션용 런타임 설정
if config_env() == :prod do
  # 환경 변수에서 Azure OpenAI 설정 로드
  config :core,
    azure_openai_endpoint:
      System.get_env("AZURE_OPENAI_ENDPOINT") ||
        raise("AZURE_OPENAI_ENDPOINT environment variable is not set"),
    azure_openai_api_key:
      System.get_env("AZURE_OPENAI_API_KEY") ||
        raise("AZURE_OPENAI_API_KEY environment variable is not set"),
    azure_openai_api_version: System.get_env("AZURE_OPENAI_API_VERSION", "2024-10-21")

  # 데이터베이스
  database_path =
    System.get_env("DATABASE_PATH") ||
      raise("DATABASE_PATH environment variable is not set")

  config :core, Core.Repo, database: database_path

  # 웹 서버
  host = System.get_env("PHX_HOST") || "localhost"
  port = String.to_integer(System.get_env("PORT") || "4000")

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise("SECRET_KEY_BASE environment variable is not set")

  config :web, WebWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base
end
