# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Re-syncs file-based sources of truth:
#   • priv/cards/*.yaml      → agentic_cards (and child taxonomies/etc.)
#   • priv/failures/*.yaml   → failure_modes (catalog)

alias AgenticAiAgent.{Design, Failures}

# ----- Cards -----
card_results = Design.load_cards_from_priv()

if card_results == [] do
  IO.puts("No card YAML files found under priv/cards/.")
else
  for {path, outcome} <- card_results do
    case outcome do
      {:ok, card} -> IO.puts("[ok]   #{path} -> #{card.slug} (#{card.name})")
      {:error, reason} -> IO.puts("[fail] #{path} -> #{inspect(reason)}")
    end
  end
end

# ----- Failure mode catalog -----
fm_results = Failures.load_catalog_from_priv()

if fm_results == [] do
  IO.puts("No failure-mode YAML files found under priv/failures/.")
else
  for {path, outcome} <- fm_results do
    case outcome do
      {:ok, mode} -> IO.puts("[ok]   #{path} -> #{mode.slug}")
      {:error, reason} -> IO.puts("[fail] #{path} -> #{inspect(reason)}")
    end
  end
end
