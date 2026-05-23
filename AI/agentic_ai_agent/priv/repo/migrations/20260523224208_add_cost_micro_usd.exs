defmodule AgenticAiAgent.Repo.Migrations.AddCostMicroUsd do
  use Ecto.Migration

  def change do
    # Stored as **micro-USD** (1 USD = 1_000_000) so even very cheap
    # embedding calls don't round to zero. Existing `cost_cents` is kept
    # for back-compat but no longer populated.
    alter table(:runs) do
      add :cost_micro_usd, :integer, default: 0
      add :prompt_tokens, :integer, default: 0
      add :completion_tokens, :integer, default: 0
    end

    alter table(:steps) do
      add :cost_micro_usd, :integer
      add :model, :string
      add :prompt_tokens, :integer
      add :completion_tokens, :integer
    end
  end
end
