defmodule ElixirGuiTodo.Repo.Migrations.CreateTodos do
  use Ecto.Migration

  def change do
    create table(:todos) do
      add :title, :string, null: false
      add :notes, :string
      add :completed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:todos, [:completed_at])
    create index(:todos, [:inserted_at])
  end
end
