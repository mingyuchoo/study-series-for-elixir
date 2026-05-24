defmodule AgenticAiAgent.Notifications.Notification do
  @moduledoc """
  A persisted operator-facing event. Surfaced on `/notifications` so
  autonomous actions don't happen silently.

  Common kinds (free-form string):

    * `"auto_promote"`   — Scheduler auto-applied an improvement proposal
    * `"auto_rollback"`  — Scheduler reverted an auto-promoted proposal
    * `"safety_blocked"` — Scheduler refused auto-promote due to safety audit
    * `"dry_run"`        — Scheduler tick was in dry-run mode (no mutation)
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "notifications" do
    field :kind, :string
    field :subject, :string
    field :body, :string

    field :proposal_id, :string
    field :run_id, :string
    field :card_slug, :string

    field :read_at, :utc_datetime

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @castable ~w(kind subject body proposal_id run_id card_slug read_at)a

  def changeset(notification, attrs) do
    notification
    |> cast(attrs, @castable)
    |> validate_required([:kind, :subject])
    |> validate_length(:subject, max: 240)
  end
end
