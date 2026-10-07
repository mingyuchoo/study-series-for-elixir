defmodule Core.Repo.Migrations.ScopeUserData do
  use Ecto.Migration

  def change do
    create table(:user_profiles, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false)
      add(:data, :map, null: false, default: %{})
      timestamps(type: :utc_datetime)
    end

    create(unique_index(:user_profiles, [:user_id]))

    alter table(:vector_rags) do
      add(:user_id, references(:users, type: :binary_id, on_delete: :delete_all))
    end

    drop(unique_index(:vector_rags, [:name]))
    create(unique_index(:vector_rags, [:user_id, :name]))
    create(index(:vector_rags, [:user_id]))
  end
end
