defmodule AgenticAiAgent.Repo.Migrations.AddProposalSafetyFields do
  use Ecto.Migration

  def change do
    alter table(:improvement_proposals) do
      # Stored as a JSON map: %{"violations" => [...], "warnings" => [...],
      #                         "score" => float, "verdict" => "pass|warn|fail"}.
      add :safety_audit, :map

      # Quick-access for queries / UI filtering. Mirrors safety_audit.verdict.
      add :safety_verdict, :string
    end

    create index(:improvement_proposals, [:safety_verdict])
  end
end
