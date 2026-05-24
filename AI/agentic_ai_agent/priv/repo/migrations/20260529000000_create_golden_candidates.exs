defmodule AgenticAiAgent.Repo.Migrations.CreateGoldenCandidates do
  use Ecto.Migration

  def change do
    create table(:golden_candidates, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # Link to the run that produced the wrong answer. nilify_all so a run
      # cleanup doesn't cascade-delete the candidate (we still want the
      # snapshot text below).
      add :run_id, references(:runs, type: :binary_id, on_delete: :nilify_all)

      # Snapshots — copied at flag time so the candidate survives even if
      # the source run is later deleted via /runs cleanup.
      add :user_input, :text, null: false
      add :assistant_answer, :text

      # Operator fills this in when promoting; the JSONL row's
      # `expected.final_answer_contains` uses this string.
      add :corrected_answer, :text

      # Optional free-form note from the chat user at flag time.
      add :user_note, :string

      # Which card this candidate is associated with (snapshot at flag).
      add :target_card_slug, :string

      add :status, :string, null: false, default: "pending"

      # Bookkeeping for promote/dismiss outcomes.
      add :promoted_to_path, :string
      add :promoted_at, :utc_datetime
      add :promoted_by, :string
      add :dismissed_reason, :string

      add :flagged_by, :string

      timestamps(type: :utc_datetime)
    end

    create index(:golden_candidates, [:status, :inserted_at])
    create index(:golden_candidates, [:run_id])
  end
end
