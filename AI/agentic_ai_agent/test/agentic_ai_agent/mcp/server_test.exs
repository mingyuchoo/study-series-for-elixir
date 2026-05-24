defmodule AgenticAiAgent.MCP.ServerTest do
  use ExUnit.Case, async: true

  alias AgenticAiAgent.MCP.Server

  defp cs(attrs), do: Server.changeset(%Server{}, attrs)

  describe "validate_required" do
    test "name is always required; command is required for the default stdio transport" do
      changeset = cs(%{})
      refute changeset.valid?
      assert {"can't be blank", _} = changeset.errors[:name]
      # transport defaults to "stdio" → command becomes required by the
      # transport-conditional validator.
      assert {"is required for stdio transport", _} = changeset.errors[:command]
    end
  end

  describe "name format" do
    test "accepts lowercase, digits, dash, underscore" do
      assert cs(%{"name" => "fs-1", "command" => "echo"}).valid?
      assert cs(%{"name" => "ab_cd", "command" => "echo"}).valid?
      assert cs(%{"name" => "a", "command" => "echo"}).valid?
    end

    test "rejects uppercase, spaces, leading dash" do
      refute cs(%{"name" => "Filesystem", "command" => "echo"}).valid?
      refute cs(%{"name" => "fs server", "command" => "echo"}).valid?
      refute cs(%{"name" => "-fs", "command" => "echo"}).valid?
    end

    test "limits length to 64 chars" do
      refute cs(%{"name" => String.duplicate("a", 65), "command" => "echo"}).valid?
    end
  end

  describe "risk_level" do
    test "defaults to medium" do
      cs = cs(%{"name" => "fs", "command" => "echo"})
      # The default lives on the schema; cast/validate doesn't strip it.
      assert cs.valid?
      assert cs |> Ecto.Changeset.apply_changes() |> Map.get(:risk_level) == "medium"
    end

    test "accepts low/medium/high/critical" do
      for r <- ~w(low medium high critical) do
        assert cs(%{"name" => "fs", "command" => "echo", "risk_level" => r}).valid?
      end
    end

    test "rejects unknown levels" do
      refute cs(%{"name" => "fs", "command" => "echo", "risk_level" => "boom"}).valid?
    end
  end

  describe "args normalization" do
    test "list of strings is wrapped as %{\"list\" => [...]}" do
      changeset = cs(%{"name" => "fs", "command" => "echo", "args" => ["a", "b"]})
      assert changeset.valid?
      server = Ecto.Changeset.apply_changes(changeset)
      assert server.args == %{"list" => ["a", "b"]}
      assert Server.args_list(server) == ["a", "b"]
    end

    test "whitespace-separated string is split into list" do
      changeset = cs(%{"name" => "fs", "command" => "echo", "args" => "-y --foo bar"})
      server = Ecto.Changeset.apply_changes(changeset)
      assert Server.args_list(server) == ["-y", "--foo", "bar"]
    end

    test "pre-wrapped %{\"list\" => [...]} passes through" do
      changeset = cs(%{"name" => "fs", "command" => "echo", "args" => %{"list" => ["x"]}})
      server = Ecto.Changeset.apply_changes(changeset)
      assert Server.args_list(server) == ["x"]
    end

    test "coerces non-string list members to strings" do
      changeset = cs(%{"name" => "fs", "command" => "echo", "args" => [1, :foo]})
      server = Ecto.Changeset.apply_changes(changeset)
      assert Server.args_list(server) == ["1", "foo"]
    end
  end

  describe "env normalization" do
    test "stringifies keys and values; drops blank keys" do
      changeset = cs(%{
        "name" => "fs",
        "command" => "echo",
        "env" => %{"FOO" => "bar", :BAZ => 42, "" => "dropped"}
      })

      env = changeset |> Ecto.Changeset.apply_changes() |> Server.env_map()

      assert env["FOO"] == "bar"
      assert env["BAZ"] == "42"
      refute Map.has_key?(env, "")
    end
  end

  describe "args_list / env_map fallbacks" do
    test "return [] / %{} for shapes missing the expected wrappers" do
      assert Server.args_list(%Server{args: %{}}) == []
      assert Server.env_map(%Server{env: %{"K" => "V"}}) == %{"K" => "V"}
    end
  end

  describe "transport" do
    test "defaults to stdio" do
      cs = cs(%{"name" => "fs", "command" => "echo"})
      assert cs.valid?
      assert cs |> Ecto.Changeset.apply_changes() |> Map.get(:transport) == "stdio"
    end

    test "rejects unknown transport" do
      cs = cs(%{"name" => "fs", "command" => "echo", "transport" => "carrier_pigeon"})
      refute cs.valid?
      assert cs.errors[:transport]
    end

    test "stdio requires command (no url required)" do
      refute cs(%{"name" => "fs", "transport" => "stdio"}).valid?
      assert cs(%{"name" => "fs", "transport" => "stdio", "command" => "echo"}).valid?
    end

    test "http_sse requires url (no command required)" do
      refute cs(%{"name" => "fs", "transport" => "http_sse"}).valid?
      refute cs(%{"name" => "fs", "transport" => "http_sse", "url" => "ftp://x"}).valid?
      assert cs(%{"name" => "fs", "transport" => "http_sse", "url" => "https://x.example/sse"}).valid?
      assert cs(%{"name" => "fs", "transport" => "http_sse", "url" => "http://x/sse"}).valid?
    end
  end

  describe "headers normalization" do
    test "stringifies keys and values; drops blank keys (parallel to env)" do
      changeset =
        cs(%{
          "name" => "fs",
          "transport" => "http_sse",
          "url" => "https://x/sse",
          "headers" => %{"Authorization" => "Bearer tok", :"X-Trace" => 1, "" => "dropped"}
        })

      headers =
        changeset
        |> Ecto.Changeset.apply_changes()
        |> Server.headers_map()

      assert headers["Authorization"] == "Bearer tok"
      assert headers["X-Trace"] == "1"
      refute Map.has_key?(headers, "")
    end
  end
end
