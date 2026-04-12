defmodule ElixirBlog.BlogTest do
  use ElixirBlog.DataCase

  alias ElixirBlog.Blog
  alias ElixirBlog.Blog.{Post, Tag}

  describe "list_tags_with_post_counts/1" do
    test "returns all tags with post counts in alphabetical order" do
      # Create tags
      tag1 = Repo.insert!(%Tag{name: "Phoenix", slug: "phoenix"})
      tag2 = Repo.insert!(%Tag{name: "Elixir", slug: "elixir"})
      tag3 = Repo.insert!(%Tag{name: "Ecto", slug: "ecto"})

      # Create posts
      post1 =
        Repo.insert!(%Post{
          slug: "elixir-post-1",
          title: "Elixir Post 1",
          author: "Test Author",
          summary: "Test summary",
          thumbnail: "test.jpg",
          published_at: ~U[2024-01-01 12:00:00Z],
          reading_time: 5,
          content_path: "elixir-post-1.md"
        })

      post2 =
        Repo.insert!(%Post{
          slug: "elixir-post-2",
          title: "Elixir Post 2",
          author: "Test Author",
          summary: "Test summary",
          thumbnail: "test.jpg",
          published_at: ~U[2024-01-02 12:00:00Z],
          reading_time: 5,
          content_path: "elixir-post-2.md"
        })

      post3 =
        Repo.insert!(%Post{
          slug: "phoenix-post-1",
          title: "Phoenix Post 1",
          author: "Test Author",
          summary: "Test summary",
          thumbnail: "test.jpg",
          published_at: ~U[2024-01-03 12:00:00Z],
          reading_time: 5,
          content_path: "phoenix-post-1.md"
        })

      # Create associations in post_tags join table
      Repo.insert_all("post_tags", [
        %{post_id: post1.id, tag_id: tag2.id, inserted_at: ~U[2024-01-01 12:00:00Z]},
        %{post_id: post2.id, tag_id: tag2.id, inserted_at: ~U[2024-01-02 12:00:00Z]},
        %{post_id: post3.id, tag_id: tag1.id, inserted_at: ~U[2024-01-03 12:00:00Z]}
      ])

      result = Blog.list_tags_with_post_counts()

      # Should be sorted alphabetically: Ecto, Elixir, Phoenix
      assert length(result) == 3

      assert [
               %{name: "Ecto", slug: "ecto", post_count: 0},
               %{name: "Elixir", slug: "elixir", post_count: 2},
               %{name: "Phoenix", slug: "phoenix", post_count: 1}
             ] = result

      # Verify all fields are present
      assert Enum.all?(result, fn tag ->
               Map.has_key?(tag, :id) and
                 Map.has_key?(tag, :name) and
                 Map.has_key?(tag, :slug) and
                 Map.has_key?(tag, :post_count)
             end)
    end

    test "returns tags sorted by post count when requested" do
      # Create tags
      tag1 = Repo.insert!(%Tag{name: "Elixir", slug: "elixir"})
      tag2 = Repo.insert!(%Tag{name: "Phoenix", slug: "phoenix"})
      tag3 = Repo.insert!(%Tag{name: "Ecto", slug: "ecto"})

      # Create posts
      post1 =
        Repo.insert!(%Post{
          slug: "phoenix-post-1",
          title: "Phoenix Post 1",
          author: "Test Author",
          summary: "Test summary",
          thumbnail: "test.jpg",
          published_at: ~U[2024-01-01 12:00:00Z],
          reading_time: 5,
          content_path: "phoenix-post-1.md"
        })

      post2 =
        Repo.insert!(%Post{
          slug: "phoenix-post-2",
          title: "Phoenix Post 2",
          author: "Test Author",
          summary: "Test summary",
          thumbnail: "test.jpg",
          published_at: ~U[2024-01-02 12:00:00Z],
          reading_time: 5,
          content_path: "phoenix-post-2.md"
        })

      post3 =
        Repo.insert!(%Post{
          slug: "phoenix-post-3",
          title: "Phoenix Post 3",
          author: "Test Author",
          summary: "Test summary",
          thumbnail: "test.jpg",
          published_at: ~U[2024-01-03 12:00:00Z],
          reading_time: 5,
          content_path: "phoenix-post-3.md"
        })

      post4 =
        Repo.insert!(%Post{
          slug: "elixir-post-1",
          title: "Elixir Post 1",
          author: "Test Author",
          summary: "Test summary",
          thumbnail: "test.jpg",
          published_at: ~U[2024-01-04 12:00:00Z],
          reading_time: 5,
          content_path: "elixir-post-1.md"
        })

      # Create associations: Phoenix (3 posts), Elixir (1 post), Ecto (0 posts)
      Repo.insert_all("post_tags", [
        %{post_id: post1.id, tag_id: tag2.id, inserted_at: ~U[2024-01-01 12:00:00Z]},
        %{post_id: post2.id, tag_id: tag2.id, inserted_at: ~U[2024-01-02 12:00:00Z]},
        %{post_id: post3.id, tag_id: tag2.id, inserted_at: ~U[2024-01-03 12:00:00Z]},
        %{post_id: post4.id, tag_id: tag1.id, inserted_at: ~U[2024-01-04 12:00:00Z]}
      ])

      result = Blog.list_tags_with_post_counts(sort: :post_count)

      # Should be sorted by post_count descending: Phoenix (3), Elixir (1), Ecto (0)
      assert length(result) == 3

      assert [
               %{name: "Phoenix", post_count: 3},
               %{name: "Elixir", post_count: 1},
               %{name: "Ecto", post_count: 0}
             ] = result
    end

    test "includes tags with zero posts" do
      # Create tag without any posts
      tag = Repo.insert!(%Tag{name: "Empty Tag", slug: "empty-tag"})

      result = Blog.list_tags_with_post_counts()

      assert length(result) == 1
      assert [%{name: "Empty Tag", slug: "empty-tag", post_count: 0}] = result
    end

    test "handles Korean tag names correctly" do
      # Create tags with Korean names
      tag1 = Repo.insert!(%Tag{name: "엘릭서", slug: "elixir-kr"})
      tag2 = Repo.insert!(%Tag{name: "피닉스", slug: "phoenix-kr"})
      tag3 = Repo.insert!(%Tag{name: "이토", slug: "ecto-kr"})

      # Create a post for one tag
      post =
        Repo.insert!(%Post{
          slug: "korean-post",
          title: "Korean Post",
          author: "Test Author",
          summary: "Test summary",
          thumbnail: "test.jpg",
          published_at: ~U[2024-01-01 12:00:00Z],
          reading_time: 5,
          content_path: "korean-post.md"
        })

      Repo.insert_all("post_tags", [
        %{post_id: post.id, tag_id: tag1.id, inserted_at: ~U[2024-01-01 12:00:00Z]}
      ])

      result = Blog.list_tags_with_post_counts()

      # Verify Korean alphabetical order (가나다순)
      # Expected order: 엘릭서, 이토, 피닉스
      assert length(result) == 3
      assert [first, second, third] = result
      assert first.name == "엘릭서"
      assert first.post_count == 1
      assert second.name == "이토"
      assert second.post_count == 0
      assert third.name == "피닉스"
      assert third.post_count == 0
    end

    test "returns empty list when no tags exist" do
      result = Blog.list_tags_with_post_counts()
      assert result == []
    end

    test "handles multiple posts associated with same tag" do
      tag = Repo.insert!(%Tag{name: "Popular", slug: "popular"})

      # Create 5 posts for the same tag
      posts =
        for i <- 1..5 do
          Repo.insert!(%Post{
            slug: "post-#{i}",
            title: "Post #{i}",
            author: "Test Author",
            summary: "Test summary",
            thumbnail: "test.jpg",
            published_at: ~U[2024-01-01 12:00:00Z],
            reading_time: 5,
            content_path: "post-#{i}.md"
          })
        end

      # Associate all posts with the tag
      associations =
        Enum.map(posts, fn post ->
          %{post_id: post.id, tag_id: tag.id, inserted_at: ~U[2024-01-01 12:00:00Z]}
        end)

      Repo.insert_all("post_tags", associations)

      result = Blog.list_tags_with_post_counts()

      assert [%{name: "Popular", post_count: 5}] = result
    end
  end
end
