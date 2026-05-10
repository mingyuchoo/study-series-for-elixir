defmodule Core.Repo.Migrations.AddUserIdToConversations do
  use Ecto.Migration

  def change do
    # 기존 dev 데이터 제거 (사용자 스코프 전환에 맞춘 클린업)
    execute "DELETE FROM messages", ""
    execute "DELETE FROM agent_interactions", ""
    execute "DELETE FROM agent_tasks", ""
    execute "DELETE FROM agent_memories", ""
    execute "DELETE FROM conversations", ""

    alter table(:conversations) do
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
    end

    create index(:conversations, [:user_id])
  end
end
