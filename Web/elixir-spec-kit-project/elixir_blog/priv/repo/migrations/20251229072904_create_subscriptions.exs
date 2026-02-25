defmodule ElixirBlog.Repo.Migrations.CreateSubscriptions do
  use Ecto.Migration

  def change do
    create table(:subscriptions) do
      add :email, :string, null: false
      add :subscribed_at, :utc_datetime, null: false

      timestamps(updated_at: false)
    end

    create unique_index(:subscriptions, [:email])
  end
end
