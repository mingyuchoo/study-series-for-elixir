defmodule ElixirGuiTodo.Todos.Todo do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  schema "todos" do
    field :title, :string
    field :notes, :string
    field :completed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(todo, attrs) do
    todo
    |> cast(attrs, [:title, :notes])
    |> validate_required([:title])
    |> validate_length(:title, max: 120)
    |> validate_length(:notes, max: 1_000)
  end
end
