defmodule AgenticAiAgent.Repo.Migrations.AddPolarityToGoldenCandidates do
  use Ecto.Migration

  def change do
    alter table(:golden_candidates) do
      # "negative" | "positive". A negative candidate is the existing
      # "this answer was wrong" snapshot (👎 / judge low-score) that
      # gets promoted with a corrected_answer to regressions.jsonl. A
      # positive candidate is "this answer was great" (👍 / judge
      # high-score) — the original `assistant_answer` IS the gold,
      # promoted to wins.jsonl so future evals confirm the agent
      # keeps producing that level of answer.
      add :polarity, :string, null: false, default: "negative"
    end

    create index(:golden_candidates, [:polarity, :status])
  end
end
