defmodule Core.Repo.Migrations.CreateMcpsTable do
  use Ecto.Migration

  def change do
    create table(:mcps, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :command, :string, null: false
      add :args, :text
      add :env, :text
      add :enabled, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:mcps, [:name])
  end
end
