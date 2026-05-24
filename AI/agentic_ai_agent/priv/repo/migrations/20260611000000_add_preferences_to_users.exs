defmodule AgenticAiAgent.Repo.Migrations.AddPreferencesToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :preferred_locale, :string, null: false, default: "en"
      add :preferred_theme, :string, null: false, default: "system"
    end
  end
end
