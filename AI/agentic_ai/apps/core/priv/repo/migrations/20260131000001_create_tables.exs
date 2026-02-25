defmodule Core.Repo.Migrations.CreateTables do
  use Ecto.Migration

  def change do
    create table(:conversations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :system_prompt, :text
      add :status, :string, default: "active"

      timestamps(type: :utc_datetime)
    end

    create table(:messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :role, :string, null: false
      add :content, :text
      add :tool_calls, :text  # JSON encoded
      add :tool_call_id, :string
      add :tokens_used, :integer

      add :conversation_id, references(:conversations, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime)
    end

    create index(:messages, [:conversation_id])
    create index(:conversations, [:status])

    create table(:tools, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :parameters, :text  # JSON encoded
      add :enabled, :boolean, default: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tools, [:name])
  end
end
