defmodule AgenticAiAgent.ImproverRollbackTest do
  # async: false — writes a real card YAML and exercises the full
  # versioning + restore stack.
  use AgenticAiAgent.DataCase, async: false

  alias AgenticAiAgent.{Design, Improver}
  alias AgenticAiAgent.Improver.{Proposal, SchedulerDecisions}

  @card_slug "rb-ui-test-#{System.unique_integer([:positive])}"

  defp seed!(role \\ "v1") do
    yaml = """
    slug: #{@card_slug}
    name: Rollback UI Test
    role: #{role}
    goal: g
    scope: s
    capabilities: {}
    tool_policy: {}
    reasoning_policy: {}
    safety_policy:
      human_approval_required_for: [high]
    output_contract: {}
    evaluation_mapping: {}
    """

    {:ok, _} = Design.save_card_source(@card_slug, yaml, reason: "seed v=#{role}")
    yaml
  end

  setup do
    seed!("v1")

    on_exit(fn ->
      case Design.card_source_path(@card_slug) do
        nil -> :ok
        path -> _ = File.rm(path)
      end
    end)

    :ok
  end

  describe "Improver.rollback!/2" do
    test ":not_applied for a pending proposal" do
      p =
        Repo.insert!(%Proposal{
          kind: "card_edit",
          target: @card_slug,
          status: "pending"
        })

      assert {:error, :not_applied} = Improver.rollback!(p, "hitl-user")
    end

    test ":already_rolled_back when called twice" do
      # First create a real applied + previous version chain.
      yaml_v2 =
        seed!("v2")
        |> String.replace("role: v1", "role: v2")

      proposal =
        Repo.insert!(%Proposal{
          kind: "card_edit",
          target: @card_slug,
          status: "approved",
          proposed_body: yaml_v2
        })

      applied = Improver.apply!(proposal, "test")
      assert applied.status == "applied"

      assert {:ok, _rolled} = Improver.rollback!(applied, "hitl-user")

      # Re-fetch to see the updated rolled_back_at.
      latest = Improver.get_proposal!(applied.id)
      assert {:error, :already_rolled_back} = Improver.rollback!(latest, "hitl-user")
    end

    test "happy path: restores prev YAML, marks rolled_back, records decision" do
      # v1 already on disk from setup. Apply a v2 via approved proposal.
      yaml_v2 = """
      slug: #{@card_slug}
      name: Rollback UI Test
      role: v2
      goal: g
      scope: s
      capabilities: {}
      tool_policy: {}
      reasoning_policy: {}
      safety_policy:
        human_approval_required_for: [high]
      output_contract: {}
      evaluation_mapping: {}
      """

      proposal =
        Repo.insert!(%Proposal{
          kind: "card_edit",
          target: @card_slug,
          status: "approved",
          proposed_body: yaml_v2
        })

      applied = Improver.apply!(proposal, "test")
      assert applied.status == "applied"

      # Disk reflects v2 now.
      assert File.read!(Design.card_source_path(@card_slug)) =~ "role: v2"

      {:ok, rolled} = Improver.rollback!(applied, "hitl-user")
      assert rolled.rolled_back_at
      assert rolled.rolled_back_reason =~ "operator rollback by hitl-user"

      # Disk back to v1.
      assert File.read!(Design.card_source_path(@card_slug)) =~ "role: v1"

      # SchedulerDecisions recorded a rolled_back action attributable to the user.
      [decision | _] = SchedulerDecisions.list(action: "rolled_back")
      assert decision.dry_run == false
      assert decision.metadata["by"] == "hitl-user"
      assert decision.proposal_id == applied.id
    end

    test ":no_previous_version when no version row predates the apply" do
      # Build a proposal whose applied_at is older than any seed version.
      ancient =
        DateTime.utc_now()
        |> DateTime.truncate(:second)
        |> DateTime.add(-365 * 86_400, :second)

      p =
        Repo.insert!(%Proposal{
          kind: "card_edit",
          target: @card_slug,
          status: "applied",
          applied_at: ancient
        })

      assert {:error, :no_previous_version} = Improver.rollback!(p, "hitl-user")

      [decision | _] = SchedulerDecisions.list(action: "no_previous_version")
      assert decision.proposal_id == p.id
    end
  end
end
