defmodule AgenticAiAgent.Tools.SpecsTest do
  # async: false because tool_specs rows are auto-synced by the running
  # Registry on app boot, and concurrent edits to the same spec across tests
  # would race. The SQL sandbox isolates inserts but not updates to pre-
  # existing rows.
  use AgenticAiAgent.DataCase, async: false

  alias AgenticAiAgent.Tools.Specs

  defp calc, do: Specs.get_spec_by_name("calculator")

  describe "list_specs/0" do
    test "returns the built-in tool specs auto-synced at boot" do
      names = Specs.list_specs() |> Enum.map(& &1.name)
      assert "calculator" in names
      assert "python_exec" in names
    end
  end

  describe "get_spec_by_name/1" do
    test "looks up a builtin by name" do
      assert %{name: "calculator"} = calc()
    end

    test "returns nil for unknown names" do
      refute Specs.get_spec_by_name("ghost-tool")
    end
  end

  describe "update/2 — risk_level / enabled" do
    test "accepts a plain field update" do
      spec = calc()
      assert {:ok, updated} = Specs.update(spec, %{"risk_level" => "high"})
      assert updated.risk_level == "high"
    end

    test "rejects an unknown risk_level" do
      spec = calc()
      assert {:error, cs} = Specs.update(spec, %{"risk_level" => "ZOMG"})
      refute cs.valid?
      assert cs.errors[:risk_level]
    end

    test "toggles enabled" do
      spec = calc()
      assert {:ok, updated} = Specs.update(spec, %{"enabled" => false})
      refute updated.enabled
    end
  end

  describe "update/2 — retry_policy" do
    test "parses a JSON string into a map" do
      spec = calc()

      assert {:ok, updated} =
               Specs.update(spec, %{"retry_policy" => ~s({"max_retries":3,"backoff_ms":500})})

      assert updated.retry_policy == %{"max_retries" => 3, "backoff_ms" => 500}
    end

    test "leaves invalid JSON for cast/3 to surface as a type error" do
      spec = calc()

      assert {:error, cs} = Specs.update(spec, %{"retry_policy" => "not json"})
      refute cs.valid?
      assert cs.errors[:retry_policy]
    end

    test "accepts a map directly" do
      spec = calc()
      assert {:ok, updated} = Specs.update(spec, %{"retry_policy" => %{"max_retries" => 1}})
      assert updated.retry_policy == %{"max_retries" => 1}
    end
  end

  describe "change/2" do
    test "returns an unvalidated changeset for forms" do
      assert %Ecto.Changeset{} = Specs.change(calc(), %{})
    end
  end
end
