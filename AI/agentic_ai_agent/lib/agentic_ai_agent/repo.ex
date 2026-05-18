defmodule AgenticAiAgent.Repo do
  use Ecto.Repo,
    otp_app: :agentic_ai_agent,
    adapter: Ecto.Adapters.SQLite3
end
