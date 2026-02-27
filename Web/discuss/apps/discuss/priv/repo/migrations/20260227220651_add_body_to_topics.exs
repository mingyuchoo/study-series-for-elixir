defmodule Discuss.Repo.Migrations.AddBodyToTopics do
  use Ecto.Migration

  def change do
    alter table(:topics) do
      add :body, :text
    end
  end
end
