defmodule AgenticAiAgent.Tools.RegistryTest do
  # async: false — Registry is a singleton GenServer shared across tests.
  # shared: true (default when not async) lets the Registry process use the
  # test's sandbox-checked-out connection.
  use AgenticAiAgent.DataCase, async: false

  alias AgenticAiAgent.Tools.Registry, as: TR

  @tool "calculator"

  setup do
    # Snapshot the live override state for the tool so we can restore it after
    # the test even though the DB row gets rolled back. The Registry cache is
    # not rolled back by the SQL sandbox, so we must explicitly restore it.
    original = %{
      "risk_level" => Atom.to_string(TR.risk_level(@tool)),
      "enabled" => TR.enabled?(@tool)
    }

    on_exit(fn ->
      _ = TR.update_spec(@tool, original)
    end)

    :ok
  end

  describe "update_spec/2 propagates to risk_level/1" do
    test "overrides the code-defined default" do
      assert TR.risk_level(@tool) == :low
      assert {:ok, _} = TR.update_spec(@tool, %{"risk_level" => "high"})
      assert TR.risk_level(@tool) == :high
    end

    test "rejects an invalid risk_level without touching the cache" do
      assert {:error, %Ecto.Changeset{}} = TR.update_spec(@tool, %{"risk_level" => "ZOMG"})
      assert TR.risk_level(@tool) == :low
    end
  end

  describe "enabled?/1 + descriptors/0 + call/2 honor disable" do
    test "disabled tool drops out of descriptors/0 and call/2 short-circuits" do
      assert TR.enabled?(@tool) == true

      assert {:ok, _} = TR.update_spec(@tool, %{"enabled" => false})

      refute TR.enabled?(@tool)
      refute Enum.any?(TR.descriptors(), &(&1["name"] == @tool))

      # Calculator's schema requires "op" + "a"; supply a valid pair so any
      # failure is from the disabled gate, not schema validation.
      assert {:error, {:tool_disabled, @tool}} =
               TR.call(@tool, %{"op" => "add", "a" => 1, "b" => 1})
    end

    test "re-enabling restores descriptors and call/2" do
      assert {:ok, _} = TR.update_spec(@tool, %{"enabled" => false})
      assert {:ok, _} = TR.update_spec(@tool, %{"enabled" => true})

      assert TR.enabled?(@tool)
      assert Enum.any?(TR.descriptors(), &(&1["name"] == @tool))
      assert {:ok, %{"result" => 2, "op" => "add"}} =
               TR.call(@tool, %{"op" => "add", "a" => 1, "b" => 1})
    end
  end

  describe "metadata/1 reflects overrides" do
    test "risk_level + enabled fields come from the spec, not the module" do
      assert {:ok, _} = TR.update_spec(@tool, %{"risk_level" => "critical", "enabled" => false})

      meta = TR.metadata(@tool)
      assert meta.risk_level == :critical
      assert meta.enabled == false
      # Code-defined fields are untouched.
      assert is_binary(meta.description)
      assert is_map(meta.input_schema)
    end

    test "returns nil for unknown tools" do
      refute TR.metadata("ghost-tool")
    end
  end

  describe "update_spec/2 broadcasts on the tools topic" do
    test "subscribers receive {:tool, :updated, name}" do
      Phoenix.PubSub.subscribe(AgenticAiAgent.PubSub, TR.pubsub_topic())

      assert {:ok, _} = TR.update_spec(@tool, %{"risk_level" => "medium"})

      assert_receive {:tool, :updated, @tool}, 500
    end
  end

  describe "update_spec/2 with unknown tool" do
    test "returns {:error, :unknown_tool}" do
      assert {:error, :unknown_tool} = TR.update_spec("ghost-tool", %{"enabled" => false})
    end
  end
end
