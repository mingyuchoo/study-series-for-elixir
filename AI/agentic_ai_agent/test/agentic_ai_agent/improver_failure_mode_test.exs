defmodule AgenticAiAgent.ImproverFailureModeTest do
  # async: false — writes a real YAML file under priv/failures/auto.
  use AgenticAiAgent.DataCase, async: false

  alias AgenticAiAgent.{Failures, Improver}
  alias AgenticAiAgent.Failures.{Clustering, FailureMode, FailureOccurrence}
  alias AgenticAiAgent.Improver.Proposal

  @auto_dir Application.compile_env(
              :agentic_ai_agent,
              :failures_auto_dir,
              "priv/failures/auto"
            )

  defp auto_path(slug),
    do: Application.app_dir(:agentic_ai_agent, @auto_dir) |> Path.join("#{slug}.yaml")

  defp slug, do: "auto_test_#{System.unique_integer([:positive])}"

  defp record!(reason, opts \\ []) do
    # `Failures.record/1` auto-classifies via Detector and ignores any
    # explicit `failure_mode_id` in attrs. To set one in tests, insert
    # the FailureOccurrence row directly.
    case Keyword.get(opts, :failure_mode_id) do
      nil ->
        {:ok, occ} = Failures.record(%{reason: reason, run_id: nil})
        occ

      mode_id ->
        Repo.insert!(%FailureOccurrence{
          failure_mode_id: mode_id,
          run_id: nil,
          reason: reason,
          detected_by: "auto"
        })
    end
  end

  defp fm_yaml(slug, opts) do
    severity = Keyword.get(opts, :severity, "medium")
    failure_type = Keyword.get(opts, :failure_type, "tool")
    name = Keyword.get(opts, :name, "Auto-discovered failure")

    """
    slug: #{slug}
    name: "#{name}"
    severity: #{severity}
    failure_type: #{failure_type}
    trigger_condition: "Cluster of unclassified failures matched this pattern."
    example: "test"
    expected_recovery: "Investigate then refine."
    detection_method: "auto: clustering"
    """
  end

  # ----- Clustering.unclassified_clusters/1 -----

  describe "Clustering.unclassified_clusters/1" do
    defmodule StubAdapter do
      @behaviour AgenticAiAgent.LLM.Embeddings

      @impl true
      def embed(texts, _opts \\ []) do
        map = Process.get(:embed_map, %{})
        vectors = Enum.map(texts, fn t -> Map.get(map, t, [0.0, 0.0, 0.0]) end)
        {:ok, %{model: "stub", vectors: vectors}}
      end
    end

    test "filters out occurrences that already have a failure_mode_id" do
      # Seed a known mode + classified occurrences against it.
      {:ok, mode} =
        Failures.upsert_mode_from_map(%{
          "slug" => "known_mode_#{System.unique_integer([:positive])}",
          "name" => "known mode"
        })

      _ = record!("classified failure A", failure_mode_id: mode.id)
      _ = record!("classified failure B", failure_mode_id: mode.id)
      _ = record!("unclassified one")
      _ = record!("unclassified two")

      Process.put(:embed_map, %{
        "classified failure A" => [1.0, 0.0, 0.0],
        "classified failure B" => [0.95, 0.0, 0.0],
        "unclassified one" => [0.0, 1.0, 0.0],
        "unclassified two" => [0.05, 0.95, 0.0]
      })

      result = Clustering.unclassified_clusters(adapter: StubAdapter)
      assert result.status == :ok
      # Only 2 unclassified were embedded; the 2 classified were filtered out.
      assert result.embedded == 2
      # The 2 unclassified form one cluster.
      assert length(result.clusters) == 1
      [c] = result.clusters
      assert c.size == 2
      assert c.exemplar_reason =~ "unclassified"
    end
  end

  # ----- failure_mode_add validation -----

  describe "failure_mode_add apply error paths" do
    test "apply marks the proposal failed when the body lacks required name" do
      target = slug()
      # YAML has slug but no name — Failures.upsert_mode_from_map will
      # produce a changeset error, and Improver should surface that
      # cleanly via status="failed" + apply_error.
      bad_body = "slug: #{target}\n"

      {:ok, p} =
        Repo.insert(
          Proposal.changeset(%Proposal{}, %{
            kind: "failure_mode_add",
            target: target,
            proposed_body: bad_body,
            status: "approved"
          })
        )

      on_exit(fn -> _ = File.rm(auto_path(target)) end)

      result = Improver.apply!(p, "tester")
      assert result.status == "failed"
      assert is_binary(result.apply_error)
      # No catalog entry was created.
      assert Failures.get_mode_by_slug(target) == nil
    end
  end

  # ----- failure_mode_add apply -----

  describe "failure_mode_add apply" do
    test "writes YAML under priv/failures/auto + upserts the mode" do
      target = slug()
      body = fm_yaml(target, severity: "high", failure_type: "tool")

      {:ok, p} =
        Repo.insert(
          Proposal.changeset(%Proposal{}, %{
            kind: "failure_mode_add",
            target: target,
            proposed_body: body,
            status: "approved"
          })
        )

      on_exit(fn ->
        _ = File.rm(auto_path(target))
      end)

      applied = Improver.apply!(p, "tester")
      assert applied.status == "applied"

      # The YAML file landed under priv/failures/auto/.
      assert File.exists?(auto_path(target))
      contents = File.read!(auto_path(target))
      assert contents =~ "slug: #{target}"
      assert contents =~ "severity: high"

      # The DB has the new mode and it's discoverable by slug.
      mode = Failures.get_mode_by_slug(target)
      assert %FailureMode{name: "Auto-discovered failure"} = mode

      # Occurrences explicitly tagged with the new mode persist + are
      # queryable. (The auto-classifier doesn't yet recognize the
      # new mode's detection_method — that's an orthogonal concern
      # tracked by the Detector module.)
      _ =
        Repo.insert!(%FailureOccurrence{
          failure_mode_id: mode.id,
          run_id: nil,
          reason: "tagged manually after catalog learned the shape",
          detected_by: "manual"
        })

      assert Repo.aggregate(
               from(o in FailureOccurrence, where: o.failure_mode_id == ^mode.id),
               :count,
               :id
             ) == 1
    end
  end

  # ----- Improver.build_context surfaces clusters + mode catalog -----

  describe "Improver.build_context — failure context" do
    alias AgenticAiAgent.Design

    setup do
      slug = "ctx-fm-#{System.unique_integer([:positive])}"

      yaml = """
      slug: #{slug}
      name: ctx fm test
      role: t
      goal: t
      scope: t
      capabilities: {}
      tool_policy: {}
      reasoning_policy: {}
      safety_policy: {}
      output_contract: {}
      evaluation_mapping: {}
      """

      {:ok, _} = Design.save_card_source(slug, yaml, reason: "seed")

      on_exit(fn ->
        case Design.card_source_path(slug) do
          nil -> :ok
          path -> _ = File.rm(path)
        end
      end)

      {:ok, slug: slug}
    end

    test "existing_failure_modes lists current catalog entries", %{slug: slug} do
      sample_slug = "ctx_sample_#{System.unique_integer([:positive])}"

      {:ok, _} =
        Failures.upsert_mode_from_map(%{
          "slug" => sample_slug,
          "name" => "ctx sample",
          "severity" => "low",
          "failure_type" => "tool"
        })

      ctx = Improver.build_context(slug, diagnose: false, cluster_failures: false)

      slugs = ctx.existing_failure_modes |> Enum.map(& &1.slug)
      assert sample_slug in slugs
    end

    test "failure_clusters is empty when no embedding adapter is configured",
         %{slug: slug} do
      # No stub installed → adapter will fail. Improver should swallow
      # the error and return [] rather than crash build_context.
      ctx = Improver.build_context(slug, diagnose: false)
      assert ctx.failure_clusters == []
    end

    test "cluster_failures: false disables embedding work entirely",
         %{slug: slug} do
      ctx = Improver.build_context(slug, diagnose: false, cluster_failures: false)
      assert ctx.failure_clusters == []
    end
  end
end
