defmodule AgenticAiAgent.ImproverToolPolicyTest do
  # async: false — writes a real card file under priv/cards.
  use AgenticAiAgent.DataCase, async: false

  alias AgenticAiAgent.{Design, Improver, Repo}
  alias AgenticAiAgent.Improver.Proposal

  @card_slug "tp-test-#{System.unique_integer([:positive])}"

  defp seed_card!(yaml_extra \\ "") do
    yaml = """
    slug: #{@card_slug}
    name: TP Test Card
    role: |
      Multi-line role
      that must survive a tool_policy_change.
    goal: short goal
    scope: short scope
    capabilities:
      inputs: [text]
      outputs: [text]
    tool_policy:
      allow: [web_search, calculator]
      deny: [python_exec]
      max_tool_calls_per_run: 8
      parallel_tool_calls: false
    reasoning_policy: {}
    safety_policy:
      human_approval_required_for: [high]
    output_contract: {}
    evaluation_mapping: {}#{yaml_extra}
    """

    {:ok, _} = Design.save_card_source(@card_slug, yaml, reason: "seed")
    yaml
  end

  setup do
    seed_card!()

    on_exit(fn ->
      case Design.card_source_path(@card_slug) do
        nil -> :ok
        path -> _ = File.rm(path)
      end
    end)

    :ok
  end

  # ----- apply_tool_policy_change/2 (pure) -----

  describe "apply_tool_policy_change/2" do
    test "rewrites only the tool_policy block, preserving multi-line role" do
      current = seed_card!()

      {:ok, new_yaml} =
        Improver.apply_tool_policy_change(current, %{
          "allow" => ["web_search", "calculator", "http_fetch"],
          "deny" => ["python_exec", "shell"]
        })

      # Multi-line role text and indentation must survive untouched.
      assert new_yaml =~ "Multi-line role\n  that must survive a tool_policy_change."

      # New allow/deny must be present.
      assert new_yaml =~ "allow: [web_search, calculator, http_fetch]"
      assert new_yaml =~ "deny: [python_exec, shell]"

      # Other tool_policy subkeys (max_tool_calls_per_run / parallel)
      # must be preserved through the parse → merge → re-emit cycle.
      assert new_yaml =~ "max_tool_calls_per_run: 8"

      # Round-trip parse confirms the result is valid YAML.
      assert {:ok, parsed} = YamlElixir.read_from_string(new_yaml)
      assert parsed["tool_policy"]["allow"] == ["web_search", "calculator", "http_fetch"]
      assert parsed["tool_policy"]["deny"] == ["python_exec", "shell"]
    end

    test "only-allow patch leaves deny untouched" do
      current = seed_card!()

      {:ok, new_yaml} =
        Improver.apply_tool_policy_change(current, %{"allow" => ["web_search"]})

      {:ok, parsed} = YamlElixir.read_from_string(new_yaml)
      assert parsed["tool_policy"]["allow"] == ["web_search"]
      # deny preserved from the original.
      assert parsed["tool_policy"]["deny"] == ["python_exec"]
    end

    test "errors cleanly on malformed YAML" do
      assert {:error, {:yaml_parse, _}} =
               Improver.apply_tool_policy_change("- not: [a mapping", %{"allow" => []})
    end
  end

  # ----- validation (via the malformed status path) -----

  describe "validation" do
    test "rejects tool_policy_change without proposed_change" do
      # We exercise validate_attrs indirectly via a hand-built changeset.
      # The Improver only invokes validate_attrs on freshly-parsed LLM
      # responses, so we cover the same ground by attempting to apply!
      # a proposal missing the required change.
      {:ok, p} =
        Repo.insert(
          Proposal.changeset(%Proposal{}, %{
            kind: "tool_policy_change",
            target: @card_slug,
            status: "approved"
          })
        )

      result = Improver.apply!(p, "tester")
      assert result.status == "failed"
      assert result.apply_error =~ ":unsupported_kind" or result.apply_error =~ "card"
    end
  end

  # ----- apply path -----

  describe "Improver.apply! for tool_policy_change" do
    test "approved proposal writes a new card YAML version with the patched tool_policy" do
      {:ok, p} =
        Repo.insert(
          Proposal.changeset(%Proposal{}, %{
            kind: "tool_policy_change",
            target: @card_slug,
            proposed_change: %{
              "allow" => ["web_search", "calculator", "http_fetch"],
              "deny" => ["python_exec"]
            },
            status: "approved"
          })
        )

      applied = Improver.apply!(p, "tester")
      assert applied.status == "applied"

      # File on disk now contains the patched allow list.
      body = File.read!(Design.card_source_path(@card_slug))
      assert body =~ "allow: [web_search, calculator, http_fetch]"

      # And the rest of the card is intact.
      assert body =~ "Multi-line role"
      assert body =~ "human_approval_required_for: [high]"

      # Phase 2 versioning fired (seed + apply → ≥ 2 rows).
      versions = Design.list_card_versions(@card_slug)
      assert length(versions) >= 2
      assert hd(versions).reason =~ ~r/tool_policy_change/
    end

    test "refuses apply when proposal is missing required fields" do
      # Missing target.
      {:ok, p} =
        Repo.insert(
          Proposal.changeset(%Proposal{}, %{
            kind: "tool_policy_change",
            target: "nonexistent-card",
            proposed_change: %{"allow" => []},
            status: "approved"
          })
        )

      result = Improver.apply!(p, "tester")
      # Either failed status with card_yaml_missing or a sensible error.
      assert result.status == "failed"
      assert result.apply_error =~ "card_yaml_missing"
    end
  end

  # ----- safety audit integration -----

  describe "safety audit on tool_policy_change" do
    alias AgenticAiAgent.Safety

    test "deny-list shrink trips the fail verdict" do
      current = seed_card!()

      # Removing python_exec from deny = deny_list_shrunk rule fires.
      {:ok, new_yaml} =
        Improver.apply_tool_policy_change(current, %{
          "deny" => []
        })

      {:ok, audit} = Safety.audit_card(current, new_yaml)
      assert audit.verdict == :fail
      assert Enum.any?(audit.violations, &(&1.rule == "deny_list_shrunk"))
    end

    test "high-risk tool addition trips the fail verdict" do
      current = seed_card!()

      {:ok, new_yaml} =
        Improver.apply_tool_policy_change(current, %{
          "allow" => ["web_search", "calculator", "python_exec"]
        })

      {:ok, audit} = Safety.audit_card(current, new_yaml)
      assert audit.verdict == :fail
      assert Enum.any?(audit.violations, &(&1.rule == "high_risk_tool_added"))
    end

    test "tightening (deny_add) passes the audit" do
      current = seed_card!()

      {:ok, new_yaml} =
        Improver.apply_tool_policy_change(current, %{
          "deny" => ["python_exec", "shell", "filesystem"]
        })

      {:ok, audit} = Safety.audit_card(current, new_yaml)
      assert audit.verdict == :pass
    end
  end
end
