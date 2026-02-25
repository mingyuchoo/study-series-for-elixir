defmodule Core.Repo.Migrations.CreateAgentsTable do
  use Ecto.Migration

  def change do
    create table(:agents, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :type, :string, null: false
      add :name, :string, null: false
      add :display_name, :string
      add :description, :text
      add :system_prompt, :text
      add :model, :string, default: "gpt-5-mini"
      add :temperature, :float, default: 1.0
      add :max_iterations, :integer, default: 10
      add :enabled_tools, :text
      add :config, :text
      add :status, :string, default: "active"
      add :created_from_markdown, :boolean, default: false
      add :markdown_path, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:agents, [:name])
    create index(:agents, [:type])
    create index(:agents, [:status])
  end
end
