defmodule ElixirBlog.Blog.TagTest do
  use ElixirBlog.DataCase

  alias ElixirBlog.Blog.Tag

  @valid_attrs %{
    name: "Elixir",
    slug: "elixir"
  }

  @invalid_attrs %{}

  describe "changeset/2" do
    test "valid changeset with all required fields" do
      changeset = Tag.changeset(%Tag{}, @valid_attrs)
      assert changeset.valid?
    end

    test "invalid changeset when required fields are missing" do
      changeset = Tag.changeset(%Tag{}, @invalid_attrs)
      refute changeset.valid?

      assert %{
               name: ["can't be blank"],
               slug: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "validates slug format allows lowercase alphanumeric and hyphens" do
      changeset = Tag.changeset(%Tag{}, %{@valid_attrs | slug: "valid-slug-123"})
      assert changeset.valid?
    end

    test "validates slug format rejects uppercase letters" do
      changeset = Tag.changeset(%Tag{}, %{@valid_attrs | slug: "Invalid-Slug"})
      refute changeset.valid?
      assert %{slug: ["has invalid format"]} = errors_on(changeset)
    end

    test "validates slug format rejects special characters" do
      changeset = Tag.changeset(%Tag{}, %{@valid_attrs | slug: "invalid_slug@123"})
      refute changeset.valid?
      assert %{slug: ["has invalid format"]} = errors_on(changeset)
    end

    test "validates slug format rejects spaces" do
      changeset = Tag.changeset(%Tag{}, %{@valid_attrs | slug: "invalid slug"})
      refute changeset.valid?
      assert %{slug: ["has invalid format"]} = errors_on(changeset)
    end

    test "validates name length maximum" do
      long_name = String.duplicate("a", 101)
      changeset = Tag.changeset(%Tag{}, %{@valid_attrs | name: long_name})
      refute changeset.valid?
      assert %{name: ["should be at most 100 character(s)"]} = errors_on(changeset)
    end

    test "validates slug length maximum" do
      long_slug = String.duplicate("a", 101)
      changeset = Tag.changeset(%Tag{}, %{@valid_attrs | slug: long_slug})
      refute changeset.valid?
      assert %{slug: ["should be at most 100 character(s)"]} = errors_on(changeset)
    end

    test "allows Korean characters in name" do
      changeset = Tag.changeset(%Tag{}, %{@valid_attrs | name: "엘릭서"})
      assert changeset.valid?
    end

    test "allows names with mixed Korean and English" do
      changeset = Tag.changeset(%Tag{}, %{@valid_attrs | name: "Elixir 프로그래밍"})
      assert changeset.valid?
    end
  end
end
