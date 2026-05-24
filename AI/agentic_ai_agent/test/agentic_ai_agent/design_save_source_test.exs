defmodule AgenticAiAgent.DesignSaveSourceTest do
  # async: false — writes a YAML file under priv/cards/ and re-uses the
  # SQL sandbox. Also competes with other tests that look at the same dir.
  use AgenticAiAgent.DataCase, async: false

  alias AgenticAiAgent.Design

  @test_slug "test-card-#{System.unique_integer([:positive])}"

  setup do
    on_exit(fn ->
      case Design.card_source_path(@test_slug) do
        nil -> :ok
        path -> _ = File.rm(path)
      end
    end)

    :ok
  end

  describe "save_card_source/2 — happy path" do
    test "writes the YAML file and upserts the DB" do
      yaml = """
      slug: #{@test_slug}
      name: Save-source Test
      role: |
        For automated test only.
      """

      assert {:ok, %{path: path, card: card}} = Design.save_card_source(@test_slug, yaml)
      assert File.exists?(path)
      assert card.slug == @test_slug
      assert card.name == "Save-source Test"
      assert Design.card_source_path(@test_slug) == path
    end
  end

  describe "save_card_source/2 — YAML parse error" do
    test "rolls back to the previous file contents" do
      good = "slug: #{@test_slug}\nname: Original\n"
      bad = ":\n  bad: ["

      assert {:ok, _} = Design.save_card_source(@test_slug, good)
      assert {:error, _} = Design.save_card_source(@test_slug, bad)

      # File still contains the original good content.
      path = Design.card_source_path(@test_slug)
      assert File.read!(path) == good
    end

    test "leaves no file if the first save fails on a non-existent slug" do
      bad = "::\n["
      assert {:error, _} = Design.save_card_source(@test_slug, bad)
      refute Design.card_source_path(@test_slug)
    end
  end
end
