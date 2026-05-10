defmodule Core.Repo.Migrations.AddAttachmentsToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :attachments, :text
    end
  end
end
