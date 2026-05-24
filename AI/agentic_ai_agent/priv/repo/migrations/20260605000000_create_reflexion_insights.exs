defmodule AgenticAiAgent.Repo.Migrations.CreateReflexionInsights do
  use Ecto.Migration

  def change do
    create table(:reflexion_insights, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # The run whose trajectory the critique evaluated. We keep the row
      # if the run is later pruned (insights drive long-term improvement,
      # not per-run debugging) — see Traces retention policy.
      add :run_id,
          references(:runs, type: :binary_id, on_delete: :nilify_all)

      # Card the run belongs to. Indexed for the recurring-themes query
      # which is per-card.
      add :card_slug, :string

      # Raw critique text as produced by Agent.Reflexion.critique/2.
      add :critique, :text, null: false

      # A coarse label extracted from the critique by
      # `ReflexionInsights.extract_theme/1` — used for grouping when we
      # ask "what is this card repeatedly failing at?". Nullable when no
      # pattern matched.
      add :theme, :string

      # Once a recurring-theme run triggers an Improver proposal, this
      # links back so the operator can see "this proposal originated
      # from these reflexions."
      add :triggered_proposal_id,
          references(:improvement_proposals, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:reflexion_insights, [:card_slug, :inserted_at])
    create index(:reflexion_insights, [:theme])
    create index(:reflexion_insights, [:triggered_proposal_id])
  end
end
