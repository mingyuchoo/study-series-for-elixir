defmodule AgenticAiAgent.Design do
  @moduledoc """
  Design layer context — Agentic Card, Task Taxonomy, Capability Matrix,
  and Workflow Graph CRUD plus a YAML loader so cards can be authored
  as files under `priv/cards/` and synced into the database.
  """

  import Ecto.Query

  alias AgenticAiAgent.Repo
  alias AgenticAiAgent.Design.{AgenticCard, CapabilityMatrix, TaskTaxonomy, WorkflowGraph}

  # ----- Queries -----

  def list_cards do
    AgenticCard
    |> order_by([c], asc: c.slug)
    |> Repo.all()
  end

  def list_cards_with_assocs do
    AgenticCard
    |> order_by([c], asc: c.slug)
    |> Repo.all()
    |> Repo.preload([:task_taxonomies, :capability_matrix, :workflow_graphs])
  end

  def get_card!(id),
    do:
      AgenticCard
      |> Repo.get!(id)
      |> Repo.preload([:task_taxonomies, :capability_matrix, :workflow_graphs])

  def get_card_by_slug(slug) when is_binary(slug) do
    AgenticCard
    |> Repo.get_by(slug: slug)
    |> case do
      nil -> nil
      card -> Repo.preload(card, [:task_taxonomies, :capability_matrix, :workflow_graphs])
    end
  end

  # ----- Upsert from parsed YAML map -----

  @doc """
  Upserts a card and its associated taxonomies/capability matrix/workflow graphs
  from a parsed YAML map (keys as strings).
  """
  def upsert_card_from_map(%{"slug" => slug} = data) do
    Repo.transaction(fn ->
      card =
        case get_card_by_slug(slug) do
          nil -> %AgenticCard{}
          existing -> existing
        end
        |> AgenticCard.changeset(card_attrs(data))
        |> Repo.insert_or_update!()

      # Replace child records on every upsert — cards are authored as files,
      # so the file is the source of truth.
      Repo.delete_all(from t in TaskTaxonomy, where: t.agentic_card_id == ^card.id)
      Repo.delete_all(from c in CapabilityMatrix, where: c.agentic_card_id == ^card.id)
      Repo.delete_all(from w in WorkflowGraph, where: w.agentic_card_id == ^card.id)

      for tx <- data["task_taxonomies"] || [] do
        %TaskTaxonomy{}
        |> TaskTaxonomy.changeset(Map.put(tx, "agentic_card_id", card.id))
        |> Repo.insert!()
      end

      if matrix = data["capability_matrix"] do
        %CapabilityMatrix{}
        |> CapabilityMatrix.changeset(Map.put(matrix, "agentic_card_id", card.id))
        |> Repo.insert!()
      end

      for wf <- data["workflow_graphs"] || [] do
        %WorkflowGraph{}
        |> WorkflowGraph.changeset(Map.put(wf, "agentic_card_id", card.id))
        |> Repo.insert!()
      end

      card
    end)
  end

  defp card_attrs(data) do
    Map.take(data, ~w(slug name role goal scope capabilities tool_policy reasoning_policy safety_policy output_contract evaluation_mapping metadata))
  end

  # ----- File loader -----

  @doc """
  Loads every YAML file under `priv/cards/` and upserts it.
  Returns a list of `{path, {:ok, card} | {:error, reason}}`.
  """
  def load_cards_from_priv do
    cards_dir = Application.app_dir(:agentic_ai_agent, "priv/cards")

    case File.ls(cards_dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, [".yaml", ".yml"]))
        |> Enum.map(fn file ->
          path = Path.join(cards_dir, file)
          {path, load_card_file(path)}
        end)

      {:error, :enoent} ->
        []
    end
  end

  defp load_card_file(path) do
    with {:ok, data} <- YamlElixir.read_from_file(path),
         {:ok, card} <- upsert_card_from_map(data) do
      {:ok, card}
    end
  end
end
