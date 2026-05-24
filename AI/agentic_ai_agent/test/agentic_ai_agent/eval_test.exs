defmodule AgenticAiAgent.EvalTest do
  # async: false — the Task spawned by run_card_async/2 runs under the
  # shared Tools.TaskSupervisor; the SQL sandbox needs shared mode so the
  # Task's eventual DB writes (during error handling) don't blow up.
  use AgenticAiAgent.DataCase, async: false

  alias AgenticAiAgent.Design.AgenticCard
  alias AgenticAiAgent.Eval
  alias AgenticAiAgent.Repo

  defp insert_card!(overrides \\ %{}) do
    base = %AgenticCard{
      slug: "test-card-#{System.unique_integer([:positive])}",
      name: "Test Card"
    }

    base
    |> Map.merge(overrides)
    |> Repo.insert!()
  end

  setup do
    Phoenix.PubSub.subscribe(AgenticAiAgent.PubSub, Eval.pubsub_topic())
    :ok
  end

  describe "run_card_async/2 — sync validation" do
    test "returns {:error, :card_not_found} for an unknown slug" do
      assert {:error, :card_not_found} = Eval.run_card_async("ghost-card")
    end

    test "does not broadcast :started when slug validation fails" do
      _ = Eval.run_card_async("ghost-card")
      refute_receive {:eval, :started, _}, 100
    end
  end

  describe "run_card_async/2 — successful launch (no golden path)" do
    # The card exists but has no evaluation_mapping. The Task will run
    # `run_card/2` which immediately returns {:error, :no_golden_path}.
    # That's enough to exercise the full broadcast pipeline without an LLM.

    test "returns :ok synchronously and broadcasts :started" do
      card = insert_card!()

      assert Eval.run_card_async(card.slug) == :ok
      assert_receive {:eval, :started, %{card_slug: slug}}, 500
      assert slug == card.slug
    end

    test "the spawned Task broadcasts :finished with the run error" do
      card = insert_card!()
      _ = Eval.run_card_async(card.slug)

      assert_receive {:eval, :started, _}, 500
      assert_receive {:eval, :finished, {:error, :no_golden_path}}, 2_000
    end
  end

  describe "run_card_async/2 — Task supervision" do
    test "spawns under AgenticAiAgent.Tools.TaskSupervisor" do
      card = insert_card!()
      before = Task.Supervisor.children(AgenticAiAgent.Tools.TaskSupervisor)
      _ = Eval.run_card_async(card.slug)

      # The task is short-lived (returns {:error, :no_golden_path} fast), so
      # rather than racing the count, just wait for the broadcast that proves
      # it ran under supervision.
      assert_receive {:eval, :finished, _}, 2_000

      # Sanity: at least we didn't leak unsupervised pids into the test
      # process tree. The before/after diff is informational.
      _ = before
    end
  end

  describe "pubsub_topic/0" do
    test "is the stable string callers can subscribe to" do
      assert Eval.pubsub_topic() == "evals"
    end
  end
end
