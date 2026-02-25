defmodule Discuss.Repo.Migrations.CreateAccountsUsersAuthTables do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS citext", ""

    create table(:accounts_users) do
      add :email, :citext, null: false
      add :hashed_password, :string, null: false
      add :confirmed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:accounts_users, [:email])

    create table(:accounts_users_tokens) do
      add :user_id, references(:accounts_users, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:accounts_users_tokens, [:user_id])
    create unique_index(:accounts_users_tokens, [:context, :token])
  end
end
