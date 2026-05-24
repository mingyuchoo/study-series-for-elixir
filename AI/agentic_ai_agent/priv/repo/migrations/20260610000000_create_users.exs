defmodule AgenticAiAgent.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :string, null: false
      add :display_name, :string, null: false
      add :password_hash, :string, null: false
      add :avatar_path, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:email])
  end
end
