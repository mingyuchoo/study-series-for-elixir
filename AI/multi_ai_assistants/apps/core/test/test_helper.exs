ExUnit.start()

# Ecto Sandbox 모드 설정 (테스트 간 DB 격리)
Ecto.Adapters.SQL.Sandbox.mode(Core.Repo, :manual)
