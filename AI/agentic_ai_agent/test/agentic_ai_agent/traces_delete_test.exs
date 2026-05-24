defmodule AgenticAiAgent.TracesDeleteTest do
  use AgenticAiAgent.DataCase, async: false

  alias AgenticAiAgent.Repo
  alias AgenticAiAgent.Traces
  alias AgenticAiAgent.Traces.Run

  # Helpers ------------------------------------------------------------------

  defp make_run!(opts \\ []) do
    %Run{
      user_input: Keyword.get(opts, :user_input, "hello"),
      status: Keyword.get(opts, :status, "done"),
      started_at: DateTime.utc_now()
    }
    |> Repo.insert!()
    |> backdate_inserted_at(opts[:inserted_at])
  end

  # Override inserted_at directly when we need a specific age. Repo.insert!
  # always stamps it with NOW, so we patch via raw UPDATE.
  defp backdate_inserted_at(run, nil), do: run

  defp backdate_inserted_at(run, %DateTime{} = ts) do
    {1, _} =
      Repo.update_all(
        from(r in Run, where: r.id == ^run.id, update: [set: [inserted_at: ^ts]]),
        []
      )

    Repo.get!(Run, run.id)
  end

  defp days_ago(n), do: DateTime.utc_now() |> DateTime.add(-n * 86_400, :second)

  # Tests --------------------------------------------------------------------

  describe "delete_run!/1" do
    test "removes the run and cascades children (steps, tool_calls, approvals)" do
      run = make_run!()
      _step = Traces.add_step!(run, :llm_call, %{"prompt" => "x"}, 100)

      assert _deleted = Traces.delete_run!(run)
      refute Repo.get(Run, run.id)
      assert Traces.list_steps(run.id) == []
    end

    test "accepts an id as well as a struct" do
      run = make_run!()
      assert _ = Traces.delete_run!(run.id)
      refute Repo.get(Run, run.id)
    end
  end

  describe "delete_runs_older_than/1" do
    test "deletes only rows older than the cutoff and returns the count" do
      _old1 = make_run!(inserted_at: days_ago(40))
      _old2 = make_run!(inserted_at: days_ago(31))
      young = make_run!(inserted_at: days_ago(15))

      assert 2 = Traces.delete_runs_older_than(30)
      assert Repo.get(Run, young.id)
      assert [%Run{id: young_id}] = Repo.all(Run)
      assert young_id == young.id
    end

    test "is inclusive — exactly-at-the-cutoff rows survive (strict <)" do
      # Insert a row stamped exactly 30 days ago. With a `< ^cutoff` check
      # it should NOT be deleted by `delete_runs_older_than(30)`.
      cutoff = days_ago(30)
      r = make_run!(inserted_at: DateTime.add(cutoff, 1, :second))

      assert 0 = Traces.delete_runs_older_than(30)
      assert Repo.get(Run, r.id)
    end

    test "refuses non-positive day values (safety guard)" do
      _ = make_run!(inserted_at: days_ago(1000))

      assert 0 = Traces.delete_runs_older_than(0)
      assert 0 = Traces.delete_runs_older_than(-5)
      assert 0 = Traces.delete_runs_older_than("nope")
    end
  end
end
