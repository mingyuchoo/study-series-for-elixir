defmodule Core.Repo.Migrations.AddVisibilityToMessages do
  use Ecto.Migration

  def up do
    alter table(:messages) do
      add :visibility, :string, default: "user_facing", null: false
    end

    flush()

    # 기존 메시지 백필:
    #  - user      → user_facing (사용자 메시지는 항상 보임 + LLM 컨텍스트 포함)
    #  - assistant → final       (지금까지의 어시스턴트 응답은 모두 최종 답변)
    #  - 그 외(system/tool) → user_facing 유지 (default)
    execute("UPDATE messages SET visibility = 'user_facing' WHERE role = 'user'")
    execute("UPDATE messages SET visibility = 'final' WHERE role = 'assistant'")

    create index(:messages, [:conversation_id, :visibility])
  end

  def down do
    drop index(:messages, [:conversation_id, :visibility])

    alter table(:messages) do
      remove :visibility
    end
  end
end
