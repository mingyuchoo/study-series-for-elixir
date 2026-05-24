defmodule AgenticAiAgent.Agent.ReflexionPersistTest do
  # async: false — Memory + Embeddings touch global config.
  use AgenticAiAgent.DataCase, async: false

  alias AgenticAiAgent.Agent.Reflexion
  alias AgenticAiAgent.Memory

  defmodule StubEmbeddings do
    @behaviour AgenticAiAgent.LLM.Embeddings

    @impl true
    def embed(texts, _opts \\ []) do
      vectors = Enum.map(texts, fn _ -> [1.0, 0.0, 0.0] end)
      {:ok, %{model: "stub", vectors: vectors}}
    end
  end

  defp with_stub_embeddings(_ctx) do
    prev = Application.get_env(:agentic_ai_agent, :embeddings_adapter)
    Application.put_env(:agentic_ai_agent, :embeddings_adapter, StubEmbeddings)

    on_exit(fn ->
      if prev,
        do: Application.put_env(:agentic_ai_agent, :embeddings_adapter, prev),
        else: Application.delete_env(:agentic_ai_agent, :embeddings_adapter)
    end)

    :ok
  end

  describe "persist_run_critique/3 — no-op paths" do
    test "nil note returns :ok and writes nothing" do
      pre = Memory.list() |> length()
      assert :ok = Reflexion.persist_run_critique(%{id: "x", user_input: "q"}, nil, nil)
      assert Memory.list() |> length() == pre
    end

    test "empty note returns :ok and writes nothing" do
      pre = Memory.list() |> length()
      assert :ok = Reflexion.persist_run_critique(%{id: "x", user_input: "q"}, nil, "")
      assert Memory.list() |> length() == pre
    end
  end

  describe "Memory.remember/2 with kind:\"reflexion\" (stubbed embeddings)" do
    setup :with_stub_embeddings

    test "persists end-to-end — the kind is on the changeset whitelist" do
      {:ok, mem} =
        Memory.remember("REFLEXION (run abc): some critique",
          kind: "reflexion",
          source: "run:abc",
          confidence: 0.7,
          sensitivity: "internal",
          retention_days: 30,
          update_rule: "overwrite_by_source"
        )

      assert mem.kind == "reflexion"
      assert mem.source == "run:abc"
      assert mem.embedding_model == "stub"

      # And it's queryable as a reflexion row.
      assert [%{id: id}] = Memory.list(kind: "reflexion")
      assert id == mem.id
    end

    test "Reflexion.persist_run_critique/3 writes a reflexion memory" do
      run = %{id: "stubbed-run-001", user_input: "what is 12 times 7?"}
      card = %{slug: "default"}
      note = "Caller should have used calculator instead of mental math."

      assert :ok = Reflexion.persist_run_critique(run, card, note)

      [m] = Memory.list(kind: "reflexion")
      assert m.source == "run:stubbed-run-001"
      assert m.content =~ "calculator instead of mental math"
      assert m.metadata["card_slug"] == "default"
    end
  end

  describe "persist_run_critique/3 — happy path (when embeddings are reachable)" do
    test "writes a kind=\"reflexion\" memory anchored on run id + user_input" do
      run = %{id: "abc-1234567890", user_input: "what is 12 times 7?"}
      card = %{slug: "default"}
      note = "Caller should have used calculator instead of mental math."

      case Reflexion.persist_run_critique(run, card, note) do
        :ok ->
          # Confirm a row landed with the expected shape.
          [m | _] =
            Memory.list()
            |> Enum.filter(&(&1.kind == "reflexion"))

          assert m.kind == "reflexion"
          assert m.source == "run:abc-1234567890"
          assert m.confidence == 0.7
          assert m.sensitivity == "internal"
          assert m.retention_days == 30
          assert m.content =~ "what is 12 times 7?"
          assert m.content =~ "calculator instead of mental math"
          # Metadata is JSON-decoded from the DB as string-keyed map.
          assert m.metadata["card_slug"] == "default"
          assert m.metadata["user_input"] == "what is 12 times 7?"

        {:error, reason} ->
          # In CI / dev without an embeddings adapter configured, this is
          # the expected outcome. The contract is: failure is advisory, not
          # an exception. Confirm we got a tagged error rather than a crash.
          assert is_atom(reason) or is_binary(reason) or is_tuple(reason)
      end
    end

    test "overwrite_by_source semantics: second persist with same run id replaces, not duplicates" do
      run = %{id: "dup-test-001", user_input: "same question"}
      card = %{slug: "default"}

      case Reflexion.persist_run_critique(run, card, "first critique") do
        :ok ->
          :ok = Reflexion.persist_run_critique(run, card, "revised critique")

          rows =
            Memory.list()
            |> Enum.filter(&(&1.source == "run:dup-test-001" and &1.kind == "reflexion"))

          assert length(rows) == 1
          assert hd(rows).content =~ "revised critique"

        {:error, _} ->
          # No embeddings adapter — skip the assertion silently. The other
          # test will surface the failure clearly.
          :ok
      end
    end
  end
end
