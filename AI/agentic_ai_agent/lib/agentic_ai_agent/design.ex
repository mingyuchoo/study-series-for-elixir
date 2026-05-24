defmodule AgenticAiAgent.Design do
  @moduledoc """
  Design layer context — Agentic Card, Task Taxonomy, Capability Matrix,
  and Workflow Graph CRUD plus a YAML loader so cards can be authored
  as files under `priv/cards/` and synced into the database.
  """

  import Ecto.Query

  alias AgenticAiAgent.Repo
  alias AgenticAiAgent.Design.{AgenticCard, CapabilityMatrix, CardVersion, TaskTaxonomy, WorkflowGraph}

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

  @doc """
  Load a single YAML card file and upsert it. Returns `{:ok, card}` or
  `{:error, reason}` (`{:yaml, ...}` for parse errors, `{:db, changeset}`
  for upsert errors).
  """
  @spec load_card_file(String.t()) :: {:ok, AgenticCard.t()} | {:error, term()}
  def load_card_file(path) do
    with {:ok, data} <- YamlElixir.read_from_file(path),
         {:ok, card} <- upsert_card_from_map(data) do
      {:ok, card}
    end
  end

  @doc """
  Absolute path to a card's source file under `priv/cards/`. Returns the
  `.yaml` path if it exists, then `.yml`, then nil.
  """
  @spec card_source_path(String.t()) :: String.t() | nil
  def card_source_path(slug) when is_binary(slug) do
    dir = Application.app_dir(:agentic_ai_agent, "priv/cards")

    Enum.find_value([".yaml", ".yml"], fn ext ->
      path = Path.join(dir, "#{slug}#{ext}")
      if File.exists?(path), do: path, else: nil
    end)
  end

  @doc """
  Atomically write a card's YAML source to `priv/cards/<slug>.yaml` and
  re-upsert into the DB. The caller is responsible for any mtime conflict
  check before invoking this. Returns `{:ok, %{path: path, card: card}}`
  or `{:error, reason}`.

  On any failure (write or upsert) the original file is restored from its
  prior contents (if it existed).

  ## Options

    * `:reason` — optional short human note recorded on the version row
      (e.g. `"restore v3"`, `"manual edit"`).
  """
  @spec save_card_source(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def save_card_source(slug, body, opts \\ []) when is_binary(slug) and is_binary(body) do
    dir = Application.app_dir(:agentic_ai_agent, "priv/cards")
    path = card_source_path(slug) || Path.join(dir, "#{slug}.yaml")

    backup = if File.exists?(path), do: File.read!(path), else: nil

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, body),
         {:ok, card} <- load_card_file(path) do
      # Successful save → snapshot for History.
      _ = snapshot_card_version(slug, body, Keyword.get(opts, :reason))
      {:ok, %{path: path, card: card}}
    else
      err ->
        # Roll back the file on validation/upsert failure.
        cond do
          backup == nil -> _ = File.rm(path)
          true -> _ = File.write(path, backup)
        end

        {:error, err}
    end
  end

  # ----- Card versions -----

  @doc """
  All historical snapshots of a card, newest first. Returns an empty
  list if the slug has no recorded history.
  """
  @spec list_card_versions(String.t()) :: [CardVersion.t()]
  def list_card_versions(slug) when is_binary(slug) do
    CardVersion
    |> where(slug: ^slug)
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  rescue
    _ -> []
  end

  @spec get_card_version!(binary()) :: CardVersion.t()
  def get_card_version!(id), do: Repo.get!(CardVersion, id)

  @doc """
  Roll the card back to a historical version. Internally calls
  `save_card_source/3` with the historical body, which writes the file,
  re-upserts the DB, and creates a fresh version row (so the rollback
  itself is auditable).
  """
  @spec restore_card_version(CardVersion.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def restore_card_version(%CardVersion{} = v, opts \\ []) do
    reason =
      Keyword.get(opts, :reason, "restore version #{short_sha(v.sha)}")

    save_card_source(v.slug, v.body, reason: reason)
  end

  @doc "Short 12-char SHA for UI display."
  def short_sha(sha) when is_binary(sha), do: String.slice(sha, 0, 12)
  def short_sha(_), do: ""

  # SHA256 of the body; idempotency guard skips writing duplicate snapshots.
  defp snapshot_card_version(slug, body, reason) do
    sha = sha256(body)

    last_sha =
      CardVersion
      |> where(slug: ^slug)
      |> order_by(desc: :inserted_at)
      |> limit(1)
      |> select([v], v.sha)
      |> Repo.one()

    if last_sha == sha do
      :ok
    else
      %CardVersion{}
      |> CardVersion.changeset(%{slug: slug, body: body, sha: sha, reason: reason})
      |> Repo.insert()
    end
  rescue
    _ -> :ok
  end

  defp sha256(body) when is_binary(body) do
    :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)
  end
end
