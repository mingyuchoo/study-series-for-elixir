defmodule AgenticAiAgent.Agent.DiagnosticsTest do
  use AgenticAiAgent.DataCase, async: false

  alias AgenticAiAgent.Agent.Diagnostics
  alias AgenticAiAgent.Design
  alias AgenticAiAgent.Failures
  alias AgenticAiAgent.Traces
  alias AgenticAiAgent.Traces.Run

  # ----- Stub LLM adapter -----
  #
  # Diagnostics is the first place we need a programmable LLM stub.
  # We hand the adapter a process-local response so each test can shape
  # what `diagnose/2` sees coming back.

  defmodule StubAdapter do
    @behaviour AgenticAiAgent.LLM.Adapter
    alias AgenticAiAgent.LLM.Response

    @impl true
    def chat(_messages, _opts) do
      case Process.get(:diagnostics_stub) do
        nil -> {:error, :no_stub_configured}
        {:ok, text} -> {:ok, %Response{content: text}}
        {:error, _} = err -> err
      end
    end
  end

  defp stub!(text) when is_binary(text), do: Process.put(:diagnostics_stub, {:ok, text})
  defp stub_error!(reason), do: Process.put(:diagnostics_stub, {:error, reason})

  # ----- Helpers -----

  defp insert_failed_run!(slug \\ nil) do
    card_id =
      case slug && Design.get_card_by_slug(slug) do
        nil -> nil
        card -> card.id
      end

    %Run{
      agentic_card_id: card_id,
      user_input: "find the latest paper on diffusion models",
      status: "failed",
      final_answer: nil,
      errors: %{"reason" => "tool web_search returned 0 results"},
      started_at: DateTime.utc_now()
    }
    |> Repo.insert!()
  end

  defp add_step!(run, kind, payload) do
    Traces.add_step!(run, kind, payload, nil)
  end

  # ----- candidate_run_ids/2 -----

  describe "candidate_run_ids/2" do
    test "returns [] when no failed runs exist for the card" do
      assert Diagnostics.candidate_run_ids("ghost-slug") == []
    end

    test "returns failed run ids in newest-first order" do
      slug = "diag-card-#{System.unique_integer([:positive])}"

      yaml = """
      slug: #{slug}
      name: Diag Test Card
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
      on_exit(fn -> _ = File.rm(Design.card_source_path(slug)) end)

      r1 = insert_failed_run!(slug)
      r2 = insert_failed_run!(slug)

      ids = Diagnostics.candidate_run_ids(slug, max_runs: 5, days: 30)
      assert r1.id in ids
      assert r2.id in ids
    end
  end

  # ----- load_trajectory/1 -----

  describe "load_trajectory/1" do
    test "loads run + steps + tool_calls + failures into one map" do
      run = insert_failed_run!()
      step = add_step!(run, :plan, %{"strategy" => "react"})
      _ = add_step!(run, :act, %{"thought" => "call web_search"})

      _ =
        Traces.add_tool_call!(run, step, %{
          tool_name: "web_search",
          input: %{"q" => ""},
          error: "empty query",
          latency_ms: 12
        })

      _ = Failures.record(%{run_id: run.id, reason: "web_search returned 0 results"})

      tr = Diagnostics.load_trajectory(run.id)
      assert tr.run.id == run.id
      assert length(tr.steps) == 2
      assert length(tr.tool_calls) == 1
      assert length(tr.failures) == 1
    end

    test "returns nil for a missing run id" do
      assert Diagnostics.load_trajectory(Ecto.UUID.generate()) == nil
    end
  end

  # ----- summarize_trajectories/1 -----

  describe "summarize_trajectories/1" do
    test "renders steps and tool errors compactly" do
      run = insert_failed_run!()
      s1 = add_step!(run, :plan, %{"strategy" => "react"})

      _ =
        Traces.add_tool_call!(run, s1, %{
          tool_name: "web_search",
          input: %{"q" => ""},
          error: "empty query",
          latency_ms: 9
        })

      tr = Diagnostics.load_trajectory(run.id)
      text = Diagnostics.summarize_trajectories([tr])

      assert text =~ "Run 1"
      assert text =~ "user_input"
      assert text =~ "[plan]"
      assert text =~ "tool=web_search"
      assert text =~ "ERROR=empty query"
    end
  end

  # ----- diagnose/2 -----

  describe "diagnose/2" do
    setup do
      Process.delete(:diagnostics_stub)
      :ok
    end

    test "parses a well-formed JSON diagnosis and attaches run ids" do
      stub!(~s({
        "summary": "planner skipped retrieve before web_search",
        "narrative": "Step 1 produced a plan that called web_search with the raw user message instead of an extracted query.",
        "recurring_pattern": "All failures lack a retrieve step before the first tool call.",
        "suggested_fix_kind": "card_edit",
        "confidence": 0.78
      }))

      run = insert_failed_run!()
      _ = add_step!(run, :plan, %{})
      tr = Diagnostics.load_trajectory(run.id)

      assert {:ok, diag} = Diagnostics.diagnose([tr], adapter: StubAdapter)
      assert diag.summary =~ "planner skipped"
      assert diag.suggested_fix_kind == "card_edit"
      assert diag.confidence == 0.78
      assert run.id in diag.run_ids
    end

    test "strips markdown fences before parsing" do
      stub!("""
      ```json
      {"summary":"x","narrative":"y","recurring_pattern":"z","suggested_fix_kind":"card_edit","confidence":0.4}
      ```
      """)

      run = insert_failed_run!()
      tr = Diagnostics.load_trajectory(run.id)

      assert {:ok, diag} = Diagnostics.diagnose([tr], adapter: StubAdapter)
      assert diag.summary == "x"
    end

    test "returns error for malformed JSON" do
      stub!("not json at all")

      run = insert_failed_run!()
      tr = Diagnostics.load_trajectory(run.id)

      assert {:error, {:json_parse, _}} = Diagnostics.diagnose([tr], adapter: StubAdapter)
    end

    test "returns error when required keys are missing" do
      stub!(~s({"summary": "only summary"}))

      run = insert_failed_run!()
      tr = Diagnostics.load_trajectory(run.id)

      assert {:error, :bad_diagnostics_shape} = Diagnostics.diagnose([tr], adapter: StubAdapter)
    end

    test "propagates adapter errors" do
      stub_error!(:timeout)

      run = insert_failed_run!()
      tr = Diagnostics.load_trajectory(run.id)

      assert {:error, :timeout} = Diagnostics.diagnose([tr], adapter: StubAdapter)
    end

    test "refuses an empty trajectory list" do
      assert {:error, :no_trajectories} = Diagnostics.diagnose([], adapter: StubAdapter)
    end

    test "clamps confidence to [0.0, 1.0]" do
      stub!(~s({
        "summary": "s", "narrative": "n", "recurring_pattern": "p",
        "suggested_fix_kind": "card_edit", "confidence": 2.5
      }))

      run = insert_failed_run!()
      tr = Diagnostics.load_trajectory(run.id)

      assert {:ok, diag} = Diagnostics.diagnose([tr], adapter: StubAdapter)
      assert diag.confidence == 1.0
    end
  end

  # ----- diagnose_card/2 -----

  describe "diagnose_card/2" do
    test "returns {:skipped, :no_failed_runs} when nothing matches" do
      assert {:skipped, :no_failed_runs} = Diagnostics.diagnose_card("ghost-slug")
    end

    test "end-to-end: picks failed runs and returns a diagnosis" do
      slug = "diag-e2e-#{System.unique_integer([:positive])}"

      yaml = """
      slug: #{slug}
      name: Diag E2E Card
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
      on_exit(fn -> _ = File.rm(Design.card_source_path(slug)) end)

      _ = insert_failed_run!(slug)
      _ = insert_failed_run!(slug)

      stub!(~s({
        "summary": "shared root cause headline",
        "narrative": "explanation",
        "recurring_pattern": "all runs missed a retrieve step",
        "suggested_fix_kind": "card_edit",
        "confidence": 0.6
      }))

      assert {:ok, diag} = Diagnostics.diagnose_card(slug, adapter: StubAdapter, days: 30)
      assert diag.summary == "shared root cause headline"
      assert length(diag.run_ids) == 2
    end
  end
end
