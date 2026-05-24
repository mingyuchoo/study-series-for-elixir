defmodule AgenticAiAgent.Repo.Migrations.AddProposalPatternFields do
  use Ecto.Migration

  def change do
    alter table(:improvement_proposals) do
      # Coarse classification of what the proposal *does* (e.g.
      # "added_retrieval", "tightened_deny", "specified_output_format").
      # Extracted heuristically from justification + root_cause_summary
      # by `AgenticAiAgent.Improver.Patterns.extract_pattern_tag/1`.
      # Drives cross-card learning: successful patterns on one card are
      # surfaced as transferable hints when proposing changes to others.
      add :pattern_tag, :string

      # Optional citation back to a prior applied proposal that the
      # proposer learned from. Set by the LLM via the `inspired_by`
      # field in its JSON response and validated against an existing
      # proposal row. `nilify_all` keeps this row if the cited
      # proposal is later deleted.
      add :inspired_by_proposal_id,
          references(:improvement_proposals, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:improvement_proposals, [:pattern_tag])
    create index(:improvement_proposals, [:inspired_by_proposal_id])
  end
end
