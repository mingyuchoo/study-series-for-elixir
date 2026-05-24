defmodule AgenticAiAgent.Agent.CharterTest do
  use ExUnit.Case, async: true

  alias AgenticAiAgent.Agent.Charter

  describe "text/0" do
    test "returns the bundled AGENTS.md contents" do
      text = Charter.text()
      # The current AGENTS.md is the operating charter, not the old Phoenix
      # coding guide. Pin to a header that should remain as long as the file
      # is the charter.
      assert is_binary(text)
      assert text =~ "Operating Charter"
    end
  end

  describe "prepend/1" do
    test "prepends charter, then horizontal rule, then body" do
      out = Charter.prepend("ROLE: tester.")
      charter = Charter.text()

      assert String.starts_with?(out, charter)
      assert String.ends_with?(out, "ROLE: tester.")
      # Exactly one HR separator between charter and body.
      assert out == charter <> "\n\n---\n\n" <> "ROLE: tester."
    end

    test "trims surrounding whitespace in the body" do
      out = Charter.prepend("   ROLE: tester.   \n")
      assert String.ends_with?(out, "ROLE: tester.")
    end

    test "returns just the charter when body is nil/empty/whitespace" do
      charter = Charter.text()

      assert Charter.prepend(nil) == charter
      assert Charter.prepend("") == charter
      assert Charter.prepend("   ") == charter
    end

    test "is idempotent in shape — calling it twice nests the charter twice" do
      # This documents current behaviour: prepend does not detect that its
      # input already contains the charter. Callers must not pre-prepend.
      once = Charter.prepend("ROLE: tester.")
      twice = Charter.prepend(once)

      assert twice != once
      assert twice =~ Charter.text()
    end
  end
end
