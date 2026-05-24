defmodule AgenticAiAgent.FeedbackTest do
  use AgenticAiAgent.DataCase, async: false

  alias AgenticAiAgent.{Feedback, Repo}
  alias AgenticAiAgent.Feedback.GoldenCandidate
  alias AgenticAiAgent.Traces.Run

  setup do
    # Use a tmp regressions path so we don't pollute the real priv file.
    # We can't easily redirect the path (it's hardcoded inside Feedback), so
    # instead we record + restore the file contents.
    path = Feedback.regressions_path()
    backup = if File.exists?(path), do: File.read!(path), else: nil

    on_exit(fn ->
      case backup do
        nil -> _ = File.rm(path)
        body -> _ = File.write(path, body)
      end
    end)

    :ok
  end

  defp insert_run!(opts \\ []) do
    %Run{
      user_input: Keyword.get(opts, :user_input, "what is 12 times 7?"),
      final_answer: Keyword.get(opts, :final_answer, "It's about 80."),
      status: Keyword.get(opts, :status, "done"),
      started_at: DateTime.utc_now()
    }
    |> Repo.insert!()
  end

  # ----- flag -----

  describe "flag/2" do
    test "snapshots user_input + assistant_answer from the run" do
      run = insert_run!()

      assert {:ok, c} = Feedback.flag(run.id, flagged_by: "tester", target_card_slug: "default")
      assert c.status == "pending"
      assert c.user_input == "what is 12 times 7?"
      assert c.assistant_answer == "It's about 80."
      assert c.run_id == run.id
      assert c.target_card_slug == "default"
      assert c.flagged_by == "tester"
    end

    test "returns :run_not_found for an unknown id" do
      assert {:error, :run_not_found} = Feedback.flag(Ecto.UUID.generate())
    end

    test "captures the user_note when provided" do
      run = insert_run!()
      {:ok, c} = Feedback.flag(run.id, user_note: "answer was off by one")
      assert c.user_note == "answer was off by one"
    end
  end

  # ----- promote -----

  describe "promote!/2" do
    test "appends a JSONL row and marks the candidate promoted" do
      run = insert_run!()
      {:ok, c} = Feedback.flag(run.id)

      {:ok, updated} = Feedback.promote!(c, corrected_answer: "84", by: "tester")

      assert updated.status == "promoted"
      assert updated.corrected_answer == "84"
      assert updated.promoted_to_path =~ "regressions.jsonl"
      assert updated.promoted_by == "tester"

      # The file now contains exactly one row with the right shape.
      body = File.read!(Feedback.regressions_path())
      [line | _] = String.split(body, "\n", trim: true) |> Enum.reverse()
      decoded = Jason.decode!(line)
      assert decoded["task_type"] == "regression"
      assert decoded["input"] == "what is 12 times 7?"
      assert decoded["expected"]["final_answer_contains"] == "84"
      assert decoded["id"] =~ ~r/^regression-/
    end

    test "refuses without a corrected answer" do
      run = insert_run!()
      {:ok, c} = Feedback.flag(run.id)
      assert {:error, :corrected_answer_required} = Feedback.promote!(c, corrected_answer: "")
    end

    test "refuses double-promote" do
      run = insert_run!()
      {:ok, c} = Feedback.flag(run.id)
      {:ok, p} = Feedback.promote!(c, corrected_answer: "84")

      assert {:error, :already_promoted} = Feedback.promote!(p, corrected_answer: "84")
    end
  end

  # ----- dismiss -----

  describe "dismiss!/2" do
    test "transitions to dismissed and captures reason" do
      run = insert_run!()
      {:ok, c} = Feedback.flag(run.id)

      dismissed = Feedback.dismiss!(c, reason: "not interesting", by: "tester")
      assert dismissed.status == "dismissed"
      assert dismissed.dismissed_reason == "not interesting"
    end
  end

  # ----- list / count_pending -----

  describe "list / count_pending" do
    test "filters by status and counts pending" do
      r1 = insert_run!()
      r2 = insert_run!(user_input: "another")

      {:ok, c1} = Feedback.flag(r1.id)
      {:ok, _} = Feedback.flag(r2.id)
      _ = Feedback.dismiss!(c1)

      assert length(Feedback.list(status: "pending")) == 1
      assert length(Feedback.list(status: "dismissed")) == 1
      assert length(Feedback.list()) == 2
      assert Feedback.count_pending() == 1
    end
  end

  describe "schema" do
    test "validates inclusion of status" do
      cs = GoldenCandidate.changeset(%GoldenCandidate{}, %{user_input: "x", status: "bogus"})
      refute cs.valid?
      assert cs.errors[:status]
    end
  end
end
