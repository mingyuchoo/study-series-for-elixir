defmodule AgenticAiAgent.VersioningTest do
  # async: false — writes real files under priv/cards & priv/skills and
  # cleans up on exit.
  use AgenticAiAgent.DataCase, async: false

  alias AgenticAiAgent.{Design, Skills}

  @card_slug "test-version-#{System.unique_integer([:positive])}"
  @skill_slug "test_version_#{System.unique_integer([:positive])}"

  setup do
    on_exit(fn ->
      # Card cleanup
      case Design.card_source_path(@card_slug) do
        nil -> :ok
        path -> _ = File.rm(path)
      end

      # Skill cleanup
      path = Skills.source_path(@skill_slug)
      _ = File.rm(path)
      _ = File.rmdir(Path.dirname(path))
      _ = Skills.reload()
    end)

    :ok
  end

  # ----- Card versioning -----

  describe "card versioning" do
    test "save_card_source creates a version row" do
      body = "slug: #{@card_slug}\nname: V1\n"
      assert {:ok, _} = Design.save_card_source(@card_slug, body, reason: "first save")

      assert [v] = Design.list_card_versions(@card_slug)
      assert v.slug == @card_slug
      assert v.body == body
      assert v.reason == "first save"
      assert String.length(v.sha) == 64
    end

    test "two saves with different bodies create two version rows" do
      _ = Design.save_card_source(@card_slug, "slug: #{@card_slug}\nname: V1\n")
      _ = Design.save_card_source(@card_slug, "slug: #{@card_slug}\nname: V2\n")

      assert length(Design.list_card_versions(@card_slug)) == 2
    end

    test "saving the same body twice is deduped (no second row)" do
      body = "slug: #{@card_slug}\nname: Same\n"
      _ = Design.save_card_source(@card_slug, body)
      _ = Design.save_card_source(@card_slug, body)

      assert length(Design.list_card_versions(@card_slug)) == 1
    end

    test "restore_card_version writes the historical body and records the rollback" do
      v1_body = "slug: #{@card_slug}\nname: V1\n"
      v2_body = "slug: #{@card_slug}\nname: V2\n"

      {:ok, _} = Design.save_card_source(@card_slug, v1_body)
      {:ok, _} = Design.save_card_source(@card_slug, v2_body)

      # Now the file is at V2. Restore back to V1.
      v1 = Design.list_card_versions(@card_slug) |> List.last()
      {:ok, _} = Design.restore_card_version(v1)

      # File contents are V1 again.
      assert File.read!(Design.card_source_path(@card_slug)) == v1_body

      # Versions: V1, V2, V1(restored). Three rows total.
      versions = Design.list_card_versions(@card_slug)
      assert length(versions) == 3
      assert List.first(versions).reason =~ ~r/restore/
    end

    test "short_sha gives a 12-char display string" do
      assert String.length(Design.short_sha(String.duplicate("a", 64))) == 12
    end
  end

  # ----- Skill versioning -----

  describe "skill versioning" do
    test "save_source creates a version row" do
      body = """
      ---
      name: #{@skill_slug}
      description: v1
      ---
      body v1
      """

      assert {:ok, _} = Skills.save_source(@skill_slug, body, reason: "initial")

      assert [v] = Skills.list_versions(@skill_slug)
      assert v.slug == @skill_slug
      assert v.body == body
      assert v.reason == "initial"
    end

    test "restore_version rolls back and records" do
      v1 = """
      ---
      name: #{@skill_slug}
      description: v1
      ---
      body v1
      """

      v2 = """
      ---
      name: #{@skill_slug}
      description: v2
      ---
      body v2
      """

      {:ok, _} = Skills.save_source(@skill_slug, v1)
      {:ok, _} = Skills.save_source(@skill_slug, v2)

      old = Skills.list_versions(@skill_slug) |> List.last()
      {:ok, _} = Skills.restore_version(old)

      assert File.read!(Skills.source_path(@skill_slug)) == v1
      assert length(Skills.list_versions(@skill_slug)) == 3
    end
  end
end
