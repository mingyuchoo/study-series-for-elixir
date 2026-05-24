defmodule AgenticAiAgent.Skills.SkillVersion do
  @moduledoc """
  A snapshot of a skill's Markdown body (frontmatter + body) at a point
  in time. See `AgenticAiAgent.Design.CardVersion` for the analogous
  schema on the card side.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "skill_versions" do
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
