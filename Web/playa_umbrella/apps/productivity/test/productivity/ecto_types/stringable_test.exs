defmodule Productivity.EctoTypes.StringableTest do
  use ExUnit.Case, async: true

  alias Productivity.EctoTypes.Stringable

  describe "type/0" do
    test "returns :string" do
      assert Stringable.type() == :string
    end
  end

  describe "load/1" do
    test "loads any value as-is" do
      assert Stringable.load("test") == {:ok, "test"}
      assert Stringable.load("") == {:ok, ""}
      assert Stringable.load(nil) == {:ok, nil}
    end
  end

  describe "cast/1" do
    test "casts atom to string" do
      assert Stringable.cast(:test) == {:ok, "test"}
      assert Stringable.cast(:hello_world) == {:ok, "hello_world"}
    end

    test "casts binary string as-is" do
      assert Stringable.cast("test") == {:ok, "test"}
      assert Stringable.cast("hello world") == {:ok, "hello world"}
      assert Stringable.cast("") == {:ok, ""}
    end

    test "casts integer to string" do
      assert Stringable.cast(123) == {:ok, "123"}
      assert Stringable.cast(0) == {:ok, "0"}
      assert Stringable.cast(-42) == {:ok, "-42"}
    end

    test "casts float to string" do
      assert Stringable.cast(3.14) == {:ok, "3.14"}
      assert Stringable.cast(0.0) == {:ok, "0.0"}
      assert Stringable.cast(-2.5) == {:ok, "-2.5"}
    end

    test "returns error for unsupported types" do
      assert Stringable.cast([1, 2, 3]) == :error
      assert Stringable.cast(%{key: "value"}) == :error
      assert Stringable.cast({:tuple, "value"}) == :error
    end
  end

  describe "dump/1" do
    test "dumps binary string as-is" do
      assert Stringable.dump("test") == {:ok, "test"}
      assert Stringable.dump("hello world") == {:ok, "hello world"}
      assert Stringable.dump("") == {:ok, ""}
    end

    test "returns error for non-binary values" do
      assert Stringable.dump(nil) == :error
      assert Stringable.dump(123) == :error
      assert Stringable.dump(:atom) == :error
      assert Stringable.dump([1, 2, 3]) == :error
      assert Stringable.dump(%{key: "value"}) == :error
    end
  end
end
