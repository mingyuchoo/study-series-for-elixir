defmodule AgenticAiAgent.ImproverSkillTest do
  # async: false — writes a real SKILL.md under priv/skills and reloads the
  # singleton Skills GenServer.
  use AgenticAiAgent.DataCase, async: false

  alias AgenticAiAgent.{Improver, Repo, Skills}
  alias AgenticAiAgent.Improver.Proposal

  @skill_slug "test_proposed_skill_#{System.unique_integer([:positive])}"

  setup do
    on_exit(fn ->
      path = Skills.source_path(@skill_slug)
      _ = File.rm(path)
      _ = File.rmdir(Path.dirname(path))
      _ = Skills.reload()
    end)

    :ok
  end

  defp valid_skill_body do
    """
    ---
    name: #{@skill_slug}
    description: Auto-proposed skill for testing.
    tools_used: [web_search]
    ---

    # #{@skill_slug}

    Step 1. ...
    """
  end

  # NOTE: validate_attrs only fires at LLM-response-parsing time inside
  # generate_proposal/1 (private). Once a row is `approved`, apply! trusts
  # the body and lets Skills.Loader decide. Skills.Loader is lax, so a body
  # without proper frontmatter still writes — that's by design for the
  # existing skill system. Validator coverage at LLM-time is exercised
  # indirectly when generate_proposal returns malformed status (covered in
  # improver_test.exs).

  # ----- apply path -----

  describe "Improver: skill_add apply path" do
    test "applies an approved skill_add proposal — writes file + creates version row" do
      {:ok, p} =
        Repo.insert(
          Proposal.changeset(%Proposal{}, %{
            kind: "skill_add",
            target: @skill_slug,
            proposed_body: valid_skill_body(),
            status: "approved"
          })
        )

      applied = Improver.apply!(p, "tester")
      assert applied.status == "applied"
      assert applied.applied_at

      # File written to disk and loadable by the Skills index.
      assert File.exists?(Skills.source_path(@skill_slug))

      slug = @skill_slug
      skill = Skills.get(slug)
      assert skill != nil
      assert skill.slug == slug

      # Phase 2 versioning fired automatically (no prior version → first row).
      versions = Skills.list_versions(@skill_slug)
      assert length(versions) == 1
      assert hd(versions).reason =~ ~r/improvement proposal/
    end
  end

  # ----- stage! refuses non-card_edit kinds -----

  describe "Improver.stage!" do
    test "refuses skill_add — no eval path for skills yet" do
      {:ok, p} =
        Repo.insert(
          Proposal.changeset(%Proposal{}, %{
            kind: "skill_add",
            target: @skill_slug,
            proposed_body: valid_skill_body(),
            status: "approved"
          })
        )

      assert {:error, {:not_stageable_kind, "skill_add"}} = Improver.stage!(p, "tester")
    end
  end
end
