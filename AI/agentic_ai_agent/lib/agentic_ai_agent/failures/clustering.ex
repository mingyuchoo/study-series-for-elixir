defmodule AgenticAiAgent.Failures.Clustering do
  @moduledoc """
  Semantic clustering of recent failure occurrences.

  Two `failure_occurrences` rows can share a `failure_mode_id` (the
  catalog classifier) but represent *very different* underlying issues
  — e.g. two `tool_error` failures, one because `web_search` returned
  empty results and one because `python_exec` hit a syntax error.
  Conversely, two unclassified rows might be the same bug expressed
  differently. The catalog can't see those clusters.

  This module groups recent reason strings by semantic similarity
  using the configured embeddings adapter. The result is a flat list
  of clusters with size, an exemplar reason, and the member ids, ready
  for the `/failures` LiveView to render.

  ## On-demand (not persisted)

  Embeddings aren't stored on the `failure_occurrences` table. The
  operator triggers clustering from the UI when they want a snapshot;
  the function embeds N reasons in one batch, clusters in-memory, and
  returns. This keeps the schema lean and avoids back-filling old
  rows.

  ## Algorithm

  Greedy single-pass agglomerative clustering on cosine similarity:

    1. Take the first failure as seed of cluster 1.
    2. For each next failure, compute cosine vs each existing cluster's
       centroid; assign to the closest cluster if similarity ≥ τ
       (default 0.78), else start a new cluster.
    3. Centroid is the running mean of member vectors.

  Cheap, deterministic, no parameter beyond τ. Good enough for the
  hundreds of recent failures a dashboard cares about; swap in k-means
  or HDBSCAN when the corpus grows past that.
  """

  alias AgenticAiAgent.Failures
  alias AgenticAiAgent.LLM.Embeddings
  alias AgenticAiAgent.Memory.Embedding

  require Logger

  @default_limit 50
  @default_threshold 0.78
  @default_min_cluster_size 2

  @typedoc "One cluster as returned to the UI."
  @type cluster :: %{
          cluster_id: pos_integer(),
          size: pos_integer(),
          exemplar_reason: String.t(),
          exemplar_occurrence_id: binary(),
          mode_slug: String.t() | nil,
          member_ids: [binary()]
        }

  @doc """
  Embed the N most recent failure reasons and cluster them. Returns a
  result map so callers (UI) can distinguish "embeddings unavailable"
  from "ran but found nothing".

  Opts:
    * `:limit` — failures to consider (default #{@default_limit})
    * `:threshold` — cosine similarity floor for cluster membership
      (default #{@default_threshold})
    * `:min_cluster_size` — drop clusters smaller than this when the
      result is rendered (default #{@default_min_cluster_size})
    * `:adapter` — override the embeddings adapter for tests
  """
  @spec cluster_recent(keyword()) :: %{
          status: :ok | :no_failures | :embedding_failed,
          clusters: [cluster()],
          singletons: non_neg_integer(),
          embedded: non_neg_integer(),
          reason: term() | nil
        }
  def cluster_recent(opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)
    threshold = Keyword.get(opts, :threshold, @default_threshold)
    min_size = Keyword.get(opts, :min_cluster_size, @default_min_cluster_size)
    adapter = Keyword.get(opts, :adapter, Embeddings.default())

    occurrences =
      Failures.list_recent_occurrences(limit)
      |> Enum.reject(&(blank?(&1.reason)))

    case occurrences do
      [] ->
        %{status: :no_failures, clusters: [], singletons: 0, embedded: 0, reason: nil}

      list ->
        embed_and_cluster(list, threshold, min_size, adapter)
    end
  rescue
    e ->
      Logger.warning("Failures.Clustering.cluster_recent/1 crashed: #{Exception.message(e)}")

      %{
        status: :embedding_failed,
        clusters: [],
        singletons: 0,
        embedded: 0,
        reason: Exception.message(e)
      }
  end

  defp embed_and_cluster(occurrences, threshold, min_size, adapter) do
    texts = Enum.map(occurrences, & &1.reason)

    case adapter.embed(texts) do
      {:ok, %{vectors: vectors}} when length(vectors) == length(occurrences) ->
        clusters = greedy_cluster(occurrences, vectors, threshold)

        {kept, singletons} = split_by_size(clusters, min_size)

        %{
          status: :ok,
          clusters: kept,
          singletons: length(singletons),
          embedded: length(occurrences),
          reason: nil
        }

      {:ok, _} ->
        %{
          status: :embedding_failed,
          clusters: [],
          singletons: 0,
          embedded: 0,
          reason: :mismatched_vector_count
        }

      {:error, reason} ->
        %{
          status: :embedding_failed,
          clusters: [],
          singletons: 0,
          embedded: 0,
          reason: reason
        }
    end
  end

  defp split_by_size(clusters, min_size) do
    Enum.split_with(clusters, &(&1.size >= min_size))
  end

  # ----- Greedy clustering -----
  #
  # State per cluster: %{centroid: [float], size: int, members: [occ]}.
  # Final mapping projects into the public `cluster` shape.

  defp greedy_cluster(occurrences, vectors, threshold) do
    occurrences
    |> Enum.zip(vectors)
    |> Enum.reduce([], fn {occ, vec}, clusters ->
      assign(clusters, occ, vec, threshold)
    end)
    |> Enum.with_index(1)
    |> Enum.map(fn {c, idx} -> finalize_cluster(c, idx) end)
    |> Enum.sort_by(& &1.size, :desc)
  end

  defp assign([], occ, vec, _threshold), do: [new_cluster(occ, vec)]

  defp assign(clusters, occ, vec, threshold) do
    {best, best_sim} = closest(clusters, vec)

    if best_sim >= threshold do
      replace(clusters, best, add_member(best, occ, vec))
    else
      clusters ++ [new_cluster(occ, vec)]
    end
  end

  defp closest([first | _] = clusters, vec) do
    Enum.reduce(clusters, {first, -1.0}, fn c, {best, best_sim} ->
      sim = Embedding.cosine(vec, c.centroid)
      if sim > best_sim, do: {c, sim}, else: {best, best_sim}
    end)
  end

  defp new_cluster(occ, vec) do
    %{
      centroid: vec,
      size: 1,
      members: [occ]
    }
  end

  defp add_member(cluster, occ, vec) do
    %{
      centroid: running_mean(cluster.centroid, cluster.size, vec),
      size: cluster.size + 1,
      members: [occ | cluster.members]
    }
  end

  # Running mean of N+1 vectors given the existing centroid and N.
  defp running_mean(centroid, n, vec) do
    factor = 1.0 / (n + 1)

    Enum.zip(centroid, vec)
    |> Enum.map(fn {c, v} -> (c * n + v) * factor end)
  end

  defp replace(list, old, new) do
    Enum.map(list, fn c -> if c == old, do: new, else: c end)
  end

  # First-inserted member is the exemplar (oldest-of-cluster, but since
  # `list_recent_occurrences` returns newest-first the actual exemplar
  # is the most-recent reason added — which is what an operator wants
  # to read).
  defp finalize_cluster(%{members: members, size: size}, cluster_id) do
    exemplar = List.last(members)
    mode = exemplar.failure_mode && exemplar.failure_mode.slug

    %{
      cluster_id: cluster_id,
      size: size,
      exemplar_reason: exemplar.reason,
      exemplar_occurrence_id: exemplar.id,
      mode_slug: mode,
      member_ids: Enum.map(members, & &1.id)
    }
  end

  # ----- Helpers -----

  defp blank?(nil), do: true
  defp blank?(s) when is_binary(s), do: String.trim(s) == ""
  defp blank?(_), do: true
end
