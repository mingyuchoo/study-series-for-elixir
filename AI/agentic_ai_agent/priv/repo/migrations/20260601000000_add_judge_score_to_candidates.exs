defmodule AgenticAiAgent.Repo.Migrations.AddJudgeScoreToCandidates do
  use Ecto.Migration

  def change do
    alter table(:golden_candidates) do
      # 0.0–1.0 quality estimate from the LLM-as-judge pass. Nil when the
      # candidate was created by a human 👎 (no judge involved).
      add :judge_score, :float
    end

    create index(:golden_candidates, [:flagged_by, :judge_score])
  end
end
