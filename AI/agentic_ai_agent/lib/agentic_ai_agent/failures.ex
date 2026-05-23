defmodule AgenticAiAgent.Failures do
  @moduledoc """
  Public API for the Failure Mode Catalog.

    * `list_modes/0`, `get_mode_by_slug/1` — read the catalog.
    * `upsert_mode_from_map/1`, `load_catalog_from_priv/0` — sync from YAML
      files under `priv/failures/`.
    * `record/1` — observe a failure (called by the runtime). Auto-classifies
      via `Detector` and persists a `FailureOccurrence` row. Returns
      `{:ok, occurrence}`.
    * `list_recent_occurrences/1`, `list_occurrences_by_mode/1` — for the
      dashboard.

  See `docs/eval.md` §12 for the conceptual model.
  """

  import Ecto.Query
  require Logger

  alias AgenticAiAgent.Repo
  alias AgenticAiAgent.Failures.{Detector, FailureMode, FailureOccurrence}

  # ----- Catalog -----

  def list_modes do
    FailureMode
    |> order_by([m], asc: m.failure_type)
    |> order_by([m], asc: m.slug)
    |> Repo.all()
  end

  def get_mode_by_slug(slug) when is_binary(slug),
    do: Repo.get_by(FailureMode, slug: slug)

  def get_mode_by_slug!(slug) when is_binary(slug),
    do: Repo.get_by!(FailureMode, slug: slug)

  def upsert_mode_from_map(%{"slug" => slug} = attrs) do
    case Repo.get_by(FailureMode, slug: slug) do
      nil -> %FailureMode{}
      existing -> existing
    end
    |> FailureMode.changeset(attrs)
    |> Repo.insert_or_update()
  end

  @doc """
  Reads every `*.yaml` / `*.yml` under `priv/failures/`. Each file may be a
  single mode or a list of modes. Returns `[{path, {:ok, mode} | {:error, _}}]`.
  """
  def load_catalog_from_priv do
    dir = Application.app_dir(:agentic_ai_agent, "priv/failures")

    case File.ls(dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, [".yaml", ".yml"]))
        |> Enum.flat_map(fn file ->
          path = Path.join(dir, file)
          load_file(path) |> Enum.map(&{path, &1})
        end)

      {:error, :enoent} ->
        []
    end
  end

  defp load_file(path) do
    case YamlElixir.read_from_file(path) do
      {:ok, list} when is_list(list) -> Enum.map(list, &upsert_mode_from_map/1)
      {:ok, %{} = map} -> [upsert_mode_from_map(map)]
      {:error, reason} -> [{:error, reason}]
    end
  end

  # ----- Occurrences -----

  @doc """
  Record an observed failure. Required keys in `attrs`:

    * `:reason` — the raw fail reason (any term). Will be classified.
    * `:run_id`

  Optional:

    * `:step_id`, `:context`, `:notes`, `:detected_by` (defaults `"auto"`).
    * `:tool_error?` — when true, route through `Detector.classify_tool_error/1`
      instead of the runtime classifier.
  """
  def record(attrs) when is_map(attrs) do
    reason = Map.get(attrs, :reason) || Map.get(attrs, "reason")
    tool? = Map.get(attrs, :tool_error?, false)

    {mode_id, summary} =
      classify(reason, tool?)

    persisted_attrs =
      %{
        failure_mode_id: mode_id,
        run_id: Map.get(attrs, :run_id) || Map.get(attrs, "run_id"),
        step_id: Map.get(attrs, :step_id) || Map.get(attrs, "step_id"),
        reason: format_reason(reason),
        context: Map.get(attrs, :context) || Map.get(attrs, "context"),
        detected_by: Map.get(attrs, :detected_by, "auto"),
        notes: Map.get(attrs, :notes) || summary
      }

    case %FailureOccurrence{}
         |> FailureOccurrence.changeset(persisted_attrs)
         |> Repo.insert() do
      {:ok, occ} ->
        {:ok, occ}

      {:error, changeset} ->
        Logger.warning("Failures.record/1 failed: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  defp classify(reason, true) do
    case Detector.classify_tool_error(reason) do
      {:ok, slug, summary} -> {mode_id_for(slug), summary}
      :unknown -> {nil, nil}
    end
  end

  defp classify(reason, _false) do
    case Detector.classify(reason) do
      {:ok, slug, summary} -> {mode_id_for(slug), summary}
      :unknown -> {nil, nil}
    end
  end

  defp mode_id_for(slug) do
    case get_mode_by_slug(slug) do
      %FailureMode{id: id} -> id
      nil -> nil
    end
  end

  defp format_reason(nil), do: nil
  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)

  # ----- Queries for the dashboard -----

  def list_recent_occurrences(limit \\ 50) do
    FailureOccurrence
    |> order_by([o], desc: o.inserted_at)
    |> limit(^limit)
    |> Repo.all()
    |> Repo.preload([:failure_mode])
  end

  def list_occurrences_by_mode(mode_id, limit \\ 100) do
    FailureOccurrence
    |> where([o], o.failure_mode_id == ^mode_id)
    |> order_by([o], desc: o.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc "Counts per mode for dashboard sparklines / lists."
  def occurrence_counts do
    FailureOccurrence
    |> group_by([o], o.failure_mode_id)
    |> select([o], {o.failure_mode_id, count(o.id)})
    |> Repo.all()
    |> Map.new()
  end

  def unclassified_count do
    Repo.one(from o in FailureOccurrence, where: is_nil(o.failure_mode_id), select: count(o.id))
  end

  def total_count do
    Repo.one(from o in FailureOccurrence, select: count(o.id))
  end
end
