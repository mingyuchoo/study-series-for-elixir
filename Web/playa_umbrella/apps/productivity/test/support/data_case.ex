defmodule Productivity.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use Productivity.DataCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias Productivity.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Productivity.DataCase
      import Playa.TestHelpers
    end
  end

  setup tags do
    Productivity.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    # Productivity and Playa repos use the same database but different schemas
    # We need to start owners for both repos to support cross-schema references
    productivity_pid =
      Ecto.Adapters.SQL.Sandbox.start_owner!(Productivity.Repo, shared: not tags[:async])

    playa_pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Playa.Repo, shared: not tags[:async])

    # Allow both repos to share the same connection for cross-schema references
    Ecto.Adapters.SQL.Sandbox.allow(Productivity.Repo, productivity_pid, self())
    Ecto.Adapters.SQL.Sandbox.allow(Playa.Repo, playa_pid, self())

    on_exit(fn ->
      Ecto.Adapters.SQL.Sandbox.stop_owner(productivity_pid)
      Ecto.Adapters.SQL.Sandbox.stop_owner(playa_pid)
    end)
  end
end
