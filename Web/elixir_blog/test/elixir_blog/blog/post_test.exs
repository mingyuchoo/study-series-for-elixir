defmodule ElixirBlog.Blog.PostTest do
  use ElixirBlog.DataCase

  alias ElixirBlog.Blog.Post

  @valid_attrs %{
    slug: "test-post",
    title: "Test Post Title",
    author: "Test Author",
    summary: "This is a test summary",
    thumbnail: "test-thumbnail.jpg",
    published_at: ~U[2024-01-01 12:00:00Z],
    reading_time: 5,
    content_path: "test-post.md"
  }

  @invalid_attrs %{}

  describe "changeset/2" do
    test "valid changeset with all required fields" do
      changeset = Post.changeset(%Post{}, @valid_attrs)
      assert changeset.valid?
    end

    test "invalid changeset when required fields are missing" do
      changeset = Post.changeset(%Post{}, @invalid_attrs)
      refute changeset.valid?

      assert %{
               slug: ["can't be blank"],
               title: ["can't be blank"],
               author: ["can't be blank"],
               summary: ["can't be blank"],
               thumbnail: ["can't be blank"],
               published_at: ["can't be blank"],
               reading_time: ["can't be blank"],
               content_path: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "validates slug format allows lowercase alphanumeric and hyphens" do
      changeset = Post.changeset(%Post{}, %{@valid_attrs | slug: "valid-slug-123"})
      assert changeset.valid?
    end

    test "validates slug format rejects uppercase letters" do
      changeset = Post.changeset(%Post{}, %{@valid_attrs | slug: "Invalid-Slug"})
      refute changeset.valid?
      assert %{slug: ["has invalid format"]} = errors_on(changeset)
    end

    test "validates slug format rejects special characters" do
      changeset = Post.changeset(%Post{}, %{@valid_attrs | slug: "invalid_slug@123"})
      refute changeset.valid?
      assert %{slug: ["has invalid format"]} = errors_on(changeset)
    end

    test "validates slug length minimum" do
      changeset = Post.changeset(%Post{}, %{@valid_attrs | slug: ""})
      refute changeset.valid?
      # Empty string triggers "can't be blank" from validate_required first
      assert %{slug: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates slug length maximum" do
      long_slug = String.duplicate("a", 256)
      changeset = Post.changeset(%Post{}, %{@valid_attrs | slug: long_slug})
      refute changeset.valid?
      assert %{slug: ["should be at most 255 character(s)"]} = errors_on(changeset)
    end

    test "validates title length maximum" do
      long_title = String.duplicate("a", 501)
      changeset = Post.changeset(%Post{}, %{@valid_attrs | title: long_title})
      refute changeset.valid?
      assert %{title: ["should be at most 500 character(s)"]} = errors_on(changeset)
    end

    test "validates author length maximum" do
      long_author = String.duplicate("a", 256)
      changeset = Post.changeset(%Post{}, %{@valid_attrs | author: long_author})
      refute changeset.valid?
      assert %{author: ["should be at most 255 character(s)"]} = errors_on(changeset)
    end

    test "validates summary length maximum" do
      long_summary = String.duplicate("a", 1001)
      changeset = Post.changeset(%Post{}, %{@valid_attrs | summary: long_summary})
      refute changeset.valid?
      assert %{summary: ["should be at most 1000 character(s)"]} = errors_on(changeset)
    end

    test "validates reading_time is greater than 0" do
      changeset = Post.changeset(%Post{}, %{@valid_attrs | reading_time: 0})
      refute changeset.valid?
      assert %{reading_time: ["must be greater than 0"]} = errors_on(changeset)
    end

    test "validates reading_time rejects negative numbers" do
      changeset = Post.changeset(%Post{}, %{@valid_attrs | reading_time: -1})
      refute changeset.valid?
      assert %{reading_time: ["must be greater than 0"]} = errors_on(changeset)
    end

    test "is_popular defaults to false" do
      changeset = Post.changeset(%Post{}, @valid_attrs)
      assert changeset.valid?
      # Default value is set in the schema, not in changeset
      assert %Post{}.is_popular == false
    end

    test "is_popular can be set to true" do
      changeset = Post.changeset(%Post{}, Map.put(@valid_attrs, :is_popular, true))
      assert changeset.valid?
      assert get_change(changeset, :is_popular) == true
    end
  end
end
