defmodule Discuss.Repo.Migrations.AddAuthUserIdToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :auth_user_id, references(:accounts_users, on_delete: :nilify_all)
    end

    create index(:users, [:auth_user_id])
  end
end
