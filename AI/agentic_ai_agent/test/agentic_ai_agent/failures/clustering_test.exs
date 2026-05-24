defmodule AgenticAiAgent.Failures.ClusteringTest do
  use AgenticAiAgent.DataCase, async: false

  alias AgenticAiAgent.Failures
  alias AgenticAiAgent.Failures.Clustering

  # Programmable stub embedder. Each test sets `:embed_map` in the
  # process dictionary mapping `reason text → 3-D vector`. The adapter
  # echoes back vectors in the input order.

  defmodule StubAdapter do
    @behaviour AgenticAiAgent.LLM.Embeddings

    @impl true
    def embed(texts, _opts \\ []) do
      map = Process.get(:embed_map, %{})

      vectors =
        Enum.map(texts, fn t ->
          Map.get(map, t, [0.0, 0.0, 0.0])
        end)

      {:ok, %{model: "stub", vectors: vectors}}
    end
  end

  defmodule ErrAdapter do
    @behaviour AgenticAiAgent.LLM.Embeddings

    @impl true
    def embed(_texts, _opts \\ []) do
      {:error, :stub_unreachable}
    end
  end

  defp record_failure!(reason) do
    {:ok, occ} = Failures.record(%{reason: reason, run_id: nil})
    occ
  end

  # ----- cluster_recent/1 -----

  describe "cluster_recent/1" do
    test ":no_failures when nothing is recorded" do
      assert %{status: :no_failures, clusters: []} =
               Clustering.cluster_recent(adapter: StubAdapter)
    end

    test "groups semantically similar reasons into one cluster" do
      # Two reasons that embed close together → same cluster.
      _ = record_failure!("web_search returned empty results for query")
      _ = record_failure!("web_search timed out after 30s waiting on results")
      _ = record_failure!("python_exec syntax error on line 42")

      Process.put(:embed_map, %{
        "web_search returned empty results for query" => [1.0, 0.0, 0.0],
        "web_search timed out after 30s waiting on results" => [0.98, 0.05, 0.05],
        "python_exec syntax error on line 42" => [0.0, 0.0, 1.0]
      })

      result = Clustering.cluster_recent(adapter: StubAdapter)
      assert result.status == :ok
      assert result.embedded == 3
      # web_search pair clusters; python_exec singleton dropped by min_size.
      assert length(result.clusters) == 1
      [c] = result.clusters
      assert c.size == 2
      assert c.exemplar_reason =~ "web_search"
      assert result.singletons == 1
    end

    test ":embedding_failed when adapter returns an error" do
      _ = record_failure!("any reason")

      assert %{status: :embedding_failed, reason: :stub_unreachable, clusters: []} =
               Clustering.cluster_recent(adapter: ErrAdapter)
    end

    test "keeps singletons when min_cluster_size=1" do
      _ = record_failure!("alone")
      Process.put(:embed_map, %{"alone" => [0.5, 0.5, 0.5]})

      result = Clustering.cluster_recent(adapter: StubAdapter, min_cluster_size: 1)
      assert result.status == :ok
      assert length(result.clusters) == 1
      assert result.singletons == 0
    end

    test "threshold controls cluster boundaries" do
      _ = record_failure!("a")
      _ = record_failure!("b")

      # Vectors are similar but below default threshold (0.78).
      Process.put(:embed_map, %{
        "a" => [1.0, 0.0, 0.0],
        "b" => [0.6, 0.8, 0.0]
      })

      # Strict threshold (0.9) splits them.
      strict =
        Clustering.cluster_recent(adapter: StubAdapter, threshold: 0.9, min_cluster_size: 1)

      assert length(strict.clusters) == 2

      # Loose threshold (0.5) merges them.
      loose = Clustering.cluster_recent(adapter: StubAdapter, threshold: 0.5)
      assert length(loose.clusters) == 1
      [c] = loose.clusters
      assert c.size == 2
    end

    test "ignores failures with blank reason" do
      {:ok, _blank} = Failures.record(%{reason: "", run_id: nil})
      _ = record_failure!("a real reason")

      Process.put(:embed_map, %{"a real reason" => [1.0, 0.0, 0.0]})

      # Only 1 reason is embedded; the blank one is dropped before the
      # adapter is called.
      result = Clustering.cluster_recent(adapter: StubAdapter, min_cluster_size: 1)
      assert result.embedded == 1
    end
  end
end
