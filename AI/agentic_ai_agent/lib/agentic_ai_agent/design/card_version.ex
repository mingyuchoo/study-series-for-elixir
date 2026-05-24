defmodule AgenticAiAgent.Design.CardVersion do
  @moduledoc """
  A snapshot of a card's YAML body at a point in time.

  Created by `Design.save_card_source/3` after every successful write,
  unless the SHA matches the previous version (no-op duplicate). Used to
  power the History UI and Restore button.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "card_versions" do
    field :slug, :string
    field :body, :string
    field :sha, :string
    field :reason, :string

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @castable ~w(slug body sha reason)a

  def changeset(version, attrs) do
    version
    |> cast(attrs, @castable)
    |> validate_required([:slug, :body, :sha])
    |> validate_length(:slug, max: 64)
  end
end
