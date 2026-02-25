defmodule Productivity.RepoTest do
  use Productivity.DataCase

  alias Productivity.Repo

  describe "Repo configuration" do
    test "repo is configured with correct otp_app" do
      assert Repo.config()[:otp_app] == :productivity
    end

    test "repo is using Postgres adapter" do
      adapter = Repo.__adapter__()
      assert adapter == Ecto.Adapters.Postgres
    end

    test "repo can perform basic queries" do
      # Test that the repo is functional by querying schemas
      result = Repo.query("SELECT 1 as value")
      assert {:ok, %Postgrex.Result{}} = result
    end
  end
end
