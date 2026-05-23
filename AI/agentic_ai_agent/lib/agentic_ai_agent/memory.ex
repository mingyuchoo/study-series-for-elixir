defmodule AgenticAiAgent.Memory do
  @moduledoc """
  Long-term memory context. Embeddings are computed via the configured
  `Embeddings` adapter, packed as float32 binaries, and stored in the
  `memories` table. Vector search is done in-process: load candidate rows,
  unpack, compute cosine similarity, sort, take top-k. Suitable for tens
  of thousands of rows on SQLite; replace with pgvector once the corpus
  outgrows that.

  Implements the Memory Schema in `docs/eval.md` §8 — kind, source,
  confidence, sensitivity, retention_days, update_rule, deletion_rule —
  with active enforcement:

    * `update_rule`
        - `append_only`        — every `remember/2` inserts a new row.
        - `overwrite_by_source` — if a memory with the same (kind, source)
          exists, its content/embedding is updated in place.
        - `overwrite_by_id`     — when an `:id` opt is provided, that row
          is replaced.
    * `deletion_rule`
        - `manual` (default)   — only explicit `delete!/1` removes it.
        - `ttl`                — `Memory.Cleaner` sweeps when
          `inserted_at + retention_days < now`.
        - `on_request`         — only `purge_on_request/1` clears it.
    * `confidence` (0.0–1.0) — multiplied into the cosine score during
      `search/2` so lower-confidence rows rank below otherwise-equal ones.
  """

  import Ecto.Query

  alias AgenticAiAgent.Repo
  alias AgenticAiAgent.LLM.Embeddings
  alias AgenticAiAgent.Memory.{Embedding, Memory}

  @default_topk 5

  # ----- CRUD -----

  def list(filters \\ []) do
    Memory
    |> apply_filters(filters)
    |> order_by([m], desc: m.inserted_at)
    |> Repo.all()
  end

  def get!(id), do: Repo.get!(Memory, id)
  def get(id), do: Repo.get(Memory, id)

  def delete!(%Memory{} = m), do: Repo.delete!(m)

  def delete_all!, do: Repo.delete_all(Memory)

  defp apply_filters(query, []), do: query

  defp apply_filters(query, filters) do
    Enum.reduce(filters, query, fn
      {:kind, kind}, q -> from m in q, where: m.kind == ^kind
      {:source, source}, q -> from m in q, where: m.source == ^source
      {:sensitivity, s}, q -> from m in q, where: m.sensitivity == ^s
      {:min_confidence, c}, q -> from m in q, where: m.confidence >= ^c
      _, q -> q
    end)
  end

  # ----- Remember (update_rule aware) -----

  @doc """
  Embed `content` and persist according to the chosen `update_rule`.
  Returns `{:ok, memory}` or `{:error, reason}`.

  Opts: `:kind`, `:source`, `:metadata`, `:confidence`, `:sensitivity`,
  `:retention_days`, `:update_rule`, `:deletion_rule`, `:id`
  (only used with `:update_rule => "overwrite_by_id"`).
  """
  def remember(content, opts \\ []) when is_binary(content) do
    opts = Map.new(opts)
    rule = Map.get(opts, :update_rule, Map.get(opts, "update_rule", "append_only"))

    case Embeddings.embed([content]) do
      {:ok, %{model: model, vectors: [vec | _]}} ->
        base =
          opts
          |> Map.merge(%{
            content: content,
            embedding: Embedding.pack(vec),
            dim: length(vec),
            embedding_model: model
          })

        persist(rule, base, opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp persist("overwrite_by_source", attrs, opts) do
    source = Map.get(opts, :source) || Map.get(opts, "source")
    kind = Map.get(opts, :kind) || Map.get(opts, "kind") || "semantic"

    case source do
      nil ->
        # without a source key we can't dedupe — fall back to append.
        do_insert(attrs)

      _ ->
        existing =
          Memory
          |> where([m], m.source == ^source and m.kind == ^kind)
          |> order_by([m], desc: m.inserted_at)
          |> limit(1)
          |> Repo.one()

        case existing do
          nil -> do_insert(attrs)
          row -> do_update(row, attrs)
        end
    end
  end

  defp persist("overwrite_by_id", attrs, opts) do
    id = Map.get(opts, :id) || Map.get(opts, "id")

    case id && Repo.get(Memory, id) do
      nil -> do_insert(attrs)
      row -> do_update(row, attrs)
    end
  end

  defp persist(_append_only, attrs, _opts), do: do_insert(attrs)

  defp do_insert(attrs) do
    {:ok, %Memory{} |> Memory.changeset(attrs) |> Repo.insert!()}
  end

  defp do_update(row, attrs) do
    # Strip identity from attrs so the changeset doesn't try to overwrite it.
    attrs = Map.drop(attrs, [:id, "id"])
    {:ok, row |> Memory.changeset(attrs) |> Repo.update!()}
  end

  # ----- Search (confidence-weighted) -----

  @doc """
  Embed `query`, score every memory by `cosine * confidence`, return top-k
  as `[{score, memory}]` sorted desc.

  Opts: `:k` (default 5), `:filters`, `:min_score`.
  """
  def search(query, opts \\ []) when is_binary(query) do
    case search_with_meta(query, opts) do
      {:ok, results, _meta} -> {:ok, results}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Same as `search/2` but additionally returns the embedding call's
  `%{model:, usage:}` so the caller can price the call. The plain
  `search/2` is kept for back-compat.
  """
  def search_with_meta(query, opts \\ []) when is_binary(query) do
    k = Keyword.get(opts, :k, @default_topk)
    filters = Keyword.get(opts, :filters, [])
    min_score = Keyword.get(opts, :min_score, 0.0)

    case Embeddings.embed([query]) do
      {:ok, %{vectors: [qvec | _]} = emb} ->
        results =
          list(filters)
          |> Enum.filter(&match?(%Memory{embedding: e} when is_binary(e), &1))
          |> Enum.map(fn m ->
            cos = Embedding.cosine_packed(qvec, m.embedding)
            confidence = m.confidence || 1.0
            {cos * confidence, m}
          end)
          |> Enum.filter(fn {s, _} -> s >= min_score end)
          |> Enum.sort_by(&elem(&1, 0), :desc)
          |> Enum.take(k)

        touch_access(results)
        {:ok, results, %{model: Map.get(emb, :model), usage: Map.get(emb, :usage)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp touch_access(results) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    ids = Enum.map(results, fn {_, m} -> m.id end)

    if ids != [] do
      Repo.update_all(
        from(m in Memory, where: m.id in ^ids),
        set: [last_accessed_at: now],
        inc: [access_count: 1]
      )
    end

    :ok
  end

  # ----- TTL sweep (deletion_rule = ttl) -----

  @doc """
  Find every memory whose `deletion_rule == "ttl"` and whose
  `inserted_at + retention_days days < now`, delete them, and return
  the count.

  Designed to be called periodically by `Memory.Cleaner` but exposed
  publicly for tests and manual triggers.
  """
  def sweep_expired do
    now = DateTime.utc_now()

    candidates =
      Memory
      |> where([m], m.deletion_rule == "ttl" and not is_nil(m.retention_days))
      |> Repo.all()

    expired_ids =
      candidates
      |> Enum.filter(fn m -> expired?(m, now) end)
      |> Enum.map(& &1.id)

    if expired_ids == [] do
      0
    else
      {n, _} = Repo.delete_all(from m in Memory, where: m.id in ^expired_ids)
      n
    end
  end

  defp expired?(%Memory{retention_days: d, inserted_at: t}, now)
       when is_integer(d) and d > 0 do
    cutoff =
      t
      |> DateTime.from_naive!("Etc/UTC")
      |> DateTime.add(d * 86_400, :second)

    DateTime.compare(now, cutoff) == :gt
  end

  defp expired?(_, _), do: false

  @doc """
  Purge every memory whose `deletion_rule == "on_request"`. Use for
  user-initiated wipes (e.g. GDPR "delete my data") — runs outside of
  the normal TTL schedule.
  """
  def purge_on_request do
    {n, _} =
      Repo.delete_all(
        from m in Memory, where: m.deletion_rule == "on_request"
      )

    n
  end

  # ----- Counts -----

  def count, do: Repo.aggregate(Memory, :count)

  def count_by_sensitivity do
    Memory
    |> group_by([m], m.sensitivity)
    |> select([m], {m.sensitivity, count(m.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc "Memories whose TTL is set but haven't yet expired, with a `:expires_at` derived field."
  def expiring_soon(within_days) when is_integer(within_days) do
    now = DateTime.utc_now()

    Memory
    |> where([m], m.deletion_rule == "ttl" and not is_nil(m.retention_days))
    |> Repo.all()
    |> Enum.map(fn m ->
      expires =
        m.inserted_at
        |> DateTime.from_naive!("Etc/UTC")
        |> DateTime.add((m.retention_days || 0) * 86_400, :second)

      {m, expires}
    end)
    |> Enum.filter(fn {_m, exp} ->
      DateTime.compare(exp, now) == :gt and
        DateTime.diff(exp, now, :second) <= within_days * 86_400
    end)
  end
end
