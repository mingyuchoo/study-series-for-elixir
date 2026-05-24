defmodule AgenticAiAgent.ImproverTest do
  # async: false — the Improver writes real card files via Design.save_card_source
  # during apply tests, and we want a stable sandbox.
  use AgenticAiAgent.DataCase, async: false

  alias AgenticAiAgent.{Design, Improver}
  alias AgenticAiAgent.Improver.Proposal

  @card_slug "imp-test-#{System.unique_integer([:positive])}"

  setup do
    # Seed a minimal card file so build_context has YAML to read.
    yaml = """
    slug: #{@card_slug}
    name: Improver Test Card
    role: original
    goal: original goal
    scope: original scope
    capabilities: {}
    tool_policy: {}
    reasoning_policy: {}
    safety_policy: {}
    output_contract: {}
    evaluation_mapping: {}
    """

    {:ok, _} = Design.save_card_source(@card_slug, yaml, reason: "seed for test")

    on_exit(fn ->
      case Design.card_source_path(@card_slug) do
        nil -> :ok
        path -> _ = File.rm(path)
      end
    end)

    :ok
  end

  # ----- build_context/1 (pure read-only, no LLM) -----

  describe "build_context/1" do
    test "returns a map with the required keys for an existing card" do
      ctx = Improver.build_context(@card_slug)

      assert ctx.slug == @card_slug
      assert ctx.window_days > 0
      assert is_map(ctx.run_health)
      assert is_list(ctx.failures_by_mode)
      assert is_list(ctx.tool_stats)
      assert is_list(ctx.regressions)
      assert is_binary(ctx.current_yaml)
      assert ctx.current_yaml =~ "Improver Test Card"
    end

    test "current_yaml is nil for a missing card" do
      ctx = Improver.build_context("ghost-card-xyz")
      assert ctx.current_yaml == nil
    end
  end

  # ----- generate_proposal/1 — early validation paths (no LLM call) -----

  describe "generate_proposal/1 — early validation" do
    test "returns :card_yaml_missing for a card with no file" do
      assert {:error, :card_yaml_missing} =
               Improver.generate_proposal("ghost-card-xyz")
    end
  end

  # ----- Decisions API directly on a hand-built proposal -----

  describe "decisions lifecycle" do
    setup do
      new_yaml = """
      slug: #{@card_slug}
      name: Improver Test Card
      role: REVISED ROLE
      goal: original goal
      scope: original scope
      capabilities: {}
      tool_policy: {}
      reasoning_policy: {}
      safety_policy: {}
      output_contract: {}
      evaluation_mapping: {}
      """

      {:ok, p} =
        %Proposal{}
        |> Proposal.changeset(%{
          kind: "card_edit",
          target: @card_slug,
          proposed_body: new_yaml,
          justification: "test-only",
          status: "pending"
        })
        |> Repo.insert()

      {:ok, proposal: p, new_yaml: new_yaml}
    end

    test "approve! transitions pending → approved", %{proposal: p} do
      updated = Improver.approve!(p, "tester")
      assert updated.status == "approved"
      assert updated.decided_by == "tester"
      assert updated.decided_at
    end

    test "reject! transitions pending → rejected with reason", %{proposal: p} do
      updated = Improver.reject!(p, "tester", "not useful")
      assert updated.status == "rejected"
      assert updated.decision_reason == "not useful"
    end

    test "apply! refuses unless approved", %{proposal: p} do
      assert {:error, {:not_approved, "pending"}} = Improver.apply!(p, "tester")
    end

    test "apply! on approved writes the YAML and produces a version row",
         %{proposal: p, new_yaml: new_yaml} do
      approved = Improver.approve!(p, "tester")
      applied = Improver.apply!(approved, "tester")

      assert applied.status == "applied"
      assert applied.applied_at

      # File on disk now contains the proposed body.
      assert File.read!(Design.card_source_path(@card_slug)) == new_yaml

      # Phase 2 versioning fired (seed save + apply save → at least 2 rows).
      versions = Design.list_card_versions(@card_slug)
      assert length(versions) >= 2
      assert hd(versions).reason =~ ~r/improvement proposal/
    end
  end

  # ----- Queue listing -----

  describe "list_proposals / count_pending" do
    test "filters by status" do
      {:ok, _p1} =
        %Proposal{}
        |> Proposal.changeset(%{kind: "card_edit", target: @card_slug, status: "pending"})
        |> Repo.insert()

      {:ok, _p2} =
        %Proposal{}
        |> Proposal.changeset(%{kind: "card_edit", target: @card_slug, status: "applied"})
        |> Repo.insert()

      assert length(Improver.list_proposals(status: "pending")) == 1
      assert length(Improver.list_proposals(status: "applied")) == 1
      assert length(Improver.list_proposals()) == 2
      assert Improver.count_pending() == 1
    end
  end

  # ----- Phase 4: staging -----

  describe "stage! / discard_staging!" do
    setup do
      new_yaml = """
      slug: #{@card_slug}
      name: Improver Test Card
      role: REVISED FOR STAGING
      goal: original goal
      scope: original scope
      capabilities: {}
      tool_policy: {}
      reasoning_policy: {}
      safety_policy: {}
      output_contract: {}
      evaluation_mapping: {}
      """

      {:ok, p} =
        %Proposal{}
        |> Proposal.changeset(%{
          kind: "card_edit",
          target: @card_slug,
          proposed_body: new_yaml,
          status: "approved"
        })
        |> Repo.insert()

      on_exit(fn ->
        staging_slug = "#{@card_slug}-staging"

        case Design.card_source_path(staging_slug) do
          nil -> :ok
          path -> _ = File.rm(path)
        end

        case Design.get_card_by_slug(staging_slug) do
          nil -> :ok
          card -> Repo.delete(card)
        end
      end)

      {:ok, proposal: p}
    end

    test "stage! creates the staging card and transitions to status=staging",
         %{proposal: p} do
      staged = Improver.stage!(p, "tester")

      assert staged.status == "staging"
      assert staged.staging_slug == "#{@card_slug}-staging"

      # File on disk exists with the rewritten slug.
      path = Design.card_source_path(staged.staging_slug)
      assert path != nil
      body = File.read!(path)
      assert body =~ "slug: #{@card_slug}-staging"
      assert body =~ "REVISED FOR STAGING"
    end

    test "stage! refuses unless proposal is approved", %{proposal: _} do
      {:ok, pending} =
        %Proposal{}
        |> Proposal.changeset(%{kind: "card_edit", target: @card_slug, status: "pending"})
        |> Repo.insert()

      assert {:error, {:not_stageable, "pending"}} = Improver.stage!(pending, "tester")
    end

    test "discard_staging! removes the staging card", %{proposal: p} do
      staged = Improver.stage!(p, "tester")
      assert File.exists?(Design.card_source_path(staged.staging_slug))

      :ok = Improver.discard_staging!(staged, "tester")

      refute Design.card_source_path(staged.staging_slug)
    end

    test "record_staging_finish! computes delta and transitions to staged_passed/failed",
         %{proposal: p} do
      # First, manually set the staging fields as if stage! were called.
      staged =
        p
        |> Proposal.changeset(%{
          status: "staging",
          staging_slug: "#{@card_slug}-staging",
          baseline_score: 0.700
        })
        |> Repo.update!()

      # Build a fake eval_run with a higher score.
      eval_run = %AgenticAiAgent.Eval.EvalRun{
        id: Ecto.UUID.generate(),
        average_score: 0.820,
        status: "done"
      }

      updated = Improver.record_staging_finish!(staged, eval_run)

      assert updated.status == "staged_passed"
      assert updated.staging_score == 0.820
      assert_in_delta updated.score_delta, 0.120, 0.001
    end

    test "record_staging_finish! with a worse staging score yields staged_failed",
         %{proposal: p} do
      staged =
        p
        |> Proposal.changeset(%{
          status: "staging",
          staging_slug: "#{@card_slug}-staging",
          baseline_score: 0.800
        })
        |> Repo.update!()

      eval_run = %AgenticAiAgent.Eval.EvalRun{
        id: Ecto.UUID.generate(),
        average_score: 0.620,
        status: "done"
      }

      updated = Improver.record_staging_finish!(staged, eval_run)

      assert updated.status == "staged_failed"
      assert_in_delta updated.score_delta, -0.180, 0.001
    end
  end
end
