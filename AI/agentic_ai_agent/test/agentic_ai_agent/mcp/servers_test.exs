defmodule AgenticAiAgent.MCP.ServersTest do
  use AgenticAiAgent.DataCase

  alias AgenticAiAgent.MCP.{Server, Servers}

  # Helpers ------------------------------------------------------------------

  # Build the minimum-valid attrs for a server. enabled defaults to false so we
  # don't poke the supervisor in tests.
  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        "name" => "test-fs",
        "command" => "echo",
        "args" => ["hello"],
        "env" => %{"FOO" => "bar"},
        "risk_level" => "medium",
        "enabled" => false
      },
      Map.new(overrides, fn {k, v} -> {to_string(k), v} end)
    )
  end

  defp create!(overrides \\ %{}) do
    {:ok, server} = Servers.create(valid_attrs(overrides))
    server
  end

  # Tests --------------------------------------------------------------------

  describe "create/1" do
    test "persists name, command, args (wrapped), env, risk, enabled=false" do
      server = create!()

      assert server.name == "test-fs"
      assert server.command == "echo"
      assert Server.args_list(server) == ["hello"]
      assert Server.env_map(server) == %{"FOO" => "bar"}
      assert server.risk_level == "medium"
      assert server.enabled == false
    end

    test "returns changeset error on invalid name" do
      assert {:error, %Ecto.Changeset{} = cs} =
               Servers.create(valid_attrs(%{"name" => "BAD UPPER"}))

      refute cs.valid?
      assert cs.errors[:name]
    end

    test "enforces unique name" do
      _ = create!()

      assert {:error, %Ecto.Changeset{} = cs} = Servers.create(valid_attrs())
      assert {_msg, [{:constraint, :unique} | _]} = cs.errors[:name]
    end
  end

  describe "list_records/0" do
    test "returns rows ordered by name asc" do
      _b = create!(%{"name" => "bbb"})
      _a = create!(%{"name" => "aaa"})

      names = Servers.list_records() |> Enum.map(& &1.name)
      assert names == ["aaa", "bbb"]
    end

    test "returns [] when the table is missing or empty" do
      assert Servers.list_records() == []
    end
  end

  describe "get_by_name/1" do
    test "looks up by name" do
      server = create!()
      assert %Server{id: id} = Servers.get_by_name(server.name)
      assert id == server.id
    end

    test "returns nil for unknown name" do
      refute Servers.get_by_name("ghost")
    end
  end

  describe "update/2" do
    test "renames the server" do
      server = create!()
      assert {:ok, updated} = Servers.update(server, %{"name" => "renamed"})
      assert updated.name == "renamed"
      refute Servers.get_by_name("test-fs")
    end

    test "normalizes args supplied as whitespace string" do
      server = create!()
      assert {:ok, updated} = Servers.update(server, %{"args" => "-a -b c"})
      assert Server.args_list(updated) == ["-a", "-b", "c"]
    end

    test "rejects invalid risk_level" do
      server = create!()
      assert {:error, cs} = Servers.update(server, %{"risk_level" => "ZOMG"})
      refute cs.valid?
    end
  end

  describe "delete/1" do
    test "removes the row" do
      server = create!()
      assert {:ok, _} = Servers.delete(server)
      refute Servers.get_by_name(server.name)
    end
  end

  describe "change/2" do
    test "returns an unvalidated changeset" do
      cs = Servers.change(%Server{}, %{"name" => "x"})
      assert %Ecto.Changeset{} = cs
    end
  end
end
