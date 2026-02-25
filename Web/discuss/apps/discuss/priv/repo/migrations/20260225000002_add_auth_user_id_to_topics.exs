defmodule Discuss.Repo.Migrations.AddAuthUserIdToTopics do
  use Ecto.Migration

  def change do
    alter table(:topics) do
      add :auth_user_id, references(:accounts_users, on_delete: :nilify_all)
    end

    create index(:topics, [:auth_user_id])
  end
end
