defmodule Productivity.ApplicationTest do
  use ExUnit.Case, async: true

  alias Productivity.Application

  describe "start/2" do
    test "application module exists and implements start/2 callback" do
      assert function_exported?(Application, :start, 2)
    end

    test "start/2 returns proper supervisor spec" do
      # Application is already started in test environment
      # We can verify that the supervisor is running
      assert Process.whereis(Productivity.Supervisor) != nil
    end

    test "required children are defined" do
      # Verify the supervisor has the expected children
      children = Supervisor.which_children(Productivity.Supervisor)

      # Extract child module names
      child_modules =
        children
        |> Enum.map(fn {name, _pid, _type, _modules} -> name end)

      # Verify core services are running
      assert Productivity.Repo in child_modules
      assert Phoenix.PubSub.Supervisor in child_modules
      assert Productivity.Finch in child_modules
    end
  end
end
