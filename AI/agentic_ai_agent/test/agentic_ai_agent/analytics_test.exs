defmodule AgenticAiAgent.AnalyticsTest do
  use AgenticAiAgent.DataCase, async: false

  alias AgenticAiAgent.Analytics
  alias AgenticAiAgent.Failures.{FailureMode, FailureOccurrence}
  alias AgenticAiAgent.Repo
  alias AgenticAiAgent.Traces.{Run, ToolCall}

  # ----- Fixture helpers -----

  defp run!(opts \\ []) do
    run =
      %Run{
        user_input: Keyword.get(opts, :user_input, "hello"),
        status: Keyword.get(opts, :status, "done"),
        latency_ms: Keyword.get(opts, :latency_ms, 100),
        cost_micro_usd: Keyword.get(opts, :cost_micro_usd, 1000),
        started_at: DateTime.utc_now()
      }
      |> Repo.insert!()

    case opts[:inserted_at] do
      nil ->
        run

      %DateTime{} = ts ->
        {1, _} =
          Repo.update_all(
            from(r in Run, where: r.id == ^run.id, update: [set: [inserted_at: ^ts]]),
            []
          )

        Repo.get!(Run, run.id)
    end
  end

  defp tool_call!(run, tool, opts \\ []) do
    %ToolCall{
      run_id: run.id,
      tool_name: tool,
      input: %{},
      output: Keyword.get(opts, :output),
      error: Keyword.get(opts, :error),
      latency_ms: Keyword.get(opts, :latency_ms, 50)
    }
    |> Repo.insert!()
  end

  defp failure_mode!(slug, opts \\ []) do
    %FailureMode{
      slug: slug,
      name: Keyword.get(opts, :name, slug),
      severity: Keyword.get(opts, :severity, "medium"),
      failure_type: Keyword.get(opts, :failure_type, "unknown")
    }
    |> Repo.insert!()
  end

  defp failure!(mode, run, opts \\ []) do
    %FailureOccurrence{
      failure_mode_id: mode.id,
      run_id: run.id,
      reason: Keyword.get(opts, :reason, "test"),
      detected_by: "test"
    }
    |> Repo.insert!()
  end

  defp days_ago(n), do: DateTime.utc_now() |> DateTime.add(-n * 86_400, :second)

  # ----- run_health/1 -----

  describe "run_health/1" do
    test "empty DB yields zero totals + nil averages" do
      h = Analytics.run_health(30)
      assert h.total == 0
      assert h.success_rate == 0.0
      assert h.avg_latency_ms == nil
    end

    test "breaks down by status and computes success rate" do
      _ = run!(status: "done", latency_ms: 100, cost_micro_usd: 2000)
      _ = run!(status: "done", latency_ms: 200, cost_micro_usd: 4000)
      _ = run!(status: "failed", latency_ms: 300, cost_micro_usd: 1000)

      h = Analytics.run_health(30)
      assert h.total == 3
      assert h.by_status == %{"done" => 2, "failed" => 1}
      assert_in_delta h.success_rate, 0.667, 0.01
      assert_in_delta h.avg_latency_ms, 200.0, 0.01
      assert h.total_cost_micro_usd == 7000
    end

    test "respects the window cutoff — old runs are excluded" do
      _ = run!(status: "done", inserted_at: days_ago(40))
      _ = run!(status: "done")

      assert Analytics.run_health(30).total == 1
      assert Analytics.run_health(60).total == 2
    end
  end

  # ----- failures_by_mode/2 -----

  describe "failures_by_mode/2" do
    test "groups by mode, counts, sorts by count desc, joins catalog" do
      timeout = failure_mode!("tool_timeout", severity: "high")
      denied = failure_mode!("tool_denied", severity: "medium")

      r1 = run!()
      r2 = run!()

      _ = failure!(timeout, r1)
      _ = failure!(timeout, r2)
      _ = failure!(denied, r1)

      result = Analytics.failures_by_mode(30)

      assert [%{slug: "tool_timeout", count: 2, severity: "high"} | _] = result
      assert Enum.find(result, &(&1.slug == "tool_denied")).count == 1
    end

    test "returns [] when no failures" do
      assert Analytics.failures_by_mode(30) == []
    end
  end

  # ----- tool_stats/1 -----

  describe "tool_stats/1" do
    test "computes calls, errors, error_rate per tool" do
      r = run!()
      tool_call!(r, "calculator", latency_ms: 10)
      tool_call!(r, "calculator", latency_ms: 30)
      tool_call!(r, "web_search", latency_ms: 200, error: "timeout")
      tool_call!(r, "web_search", latency_ms: 200)
      tool_call!(r, "web_search", latency_ms: 200, error: "5xx")

      stats = Analytics.tool_stats(30) |> Map.new(&{&1.tool, &1})

      assert stats["calculator"].calls == 2
      assert stats["calculator"].errors == 0
      assert stats["calculator"].error_rate == 0.0

      assert stats["web_search"].calls == 3
      assert stats["web_search"].errors == 2
      assert_in_delta stats["web_search"].error_rate, 0.667, 0.01
    end

    test "returns [] for an empty window" do
      assert Analytics.tool_stats(30) == []
    end
  end

  # ----- daily_cost_quality/1 -----

  describe "daily_cost_quality/1" do
    test "groups runs by date and sums cost" do
      _ = run!(cost_micro_usd: 500, inserted_at: days_ago(2))
      _ = run!(cost_micro_usd: 500, inserted_at: days_ago(2))
      _ = run!(cost_micro_usd: 1000, inserted_at: days_ago(1))

      rows = Analytics.daily_cost_quality(30)
      assert length(rows) == 2

      [older, newer] = rows
      assert older.runs == 2 and older.cost_micro_usd == 1000
      assert newer.runs == 1 and newer.cost_micro_usd == 1000
    end
  end

  # ----- recent_regressions/2 -----

  describe "recent_regressions/2" do
    test "returns only failed runs, sorted desc" do
      _ = run!(status: "done")
      old_fail = run!(status: "failed", inserted_at: days_ago(2))
      new_fail = run!(status: "failed")

      result = Analytics.recent_regressions(30, 5)
      assert Enum.map(result, & &1.id) == [new_fail.id, old_fail.id]
    end
  end
end
