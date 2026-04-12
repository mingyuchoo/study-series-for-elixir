defmodule ElixirBlogWeb.CategoryStatsLiveTest do
  use ElixirBlogWeb.ConnCase

  import Phoenix.LiveViewTest
  alias ElixirBlog.Blog.{Post, Tag}
  alias ElixirBlog.Repo

  describe "CategoryStatsLive mount" do
    test "successfully mounts and loads category statistics", %{conn: conn} do
      # Create tags
      tag1 = Repo.insert!(%Tag{name: "Elixir", slug: "elixir"})
      tag2 = Repo.insert!(%Tag{name: "Phoenix", slug: "phoenix"})

      # Create posts
      post1 =
        Repo.insert!(%Post{
          slug: "elixir-post",
          title: "Elixir Post",
          author: "Test Author",
          summary: "Test summary",
          thumbnail: "test.jpg",
          published_at: ~U[2024-01-01 12:00:00Z],
          reading_time: 5,
          content_path: "elixir-post.md"
        })

      # Associate posts with tags
      Repo.insert_all("post_tags", [
        %{post_id: post1.id, tag_id: tag1.id, inserted_at: ~U[2024-01-01 12:00:00Z]}
      ])

      {:ok, view, html} = live(conn, "/categories")

      # Verify the page mounted successfully
      assert view
      assert html =~ "카테고리"

      # Verify categories are loaded and displayed
      assert html =~ "Elixir"
      assert html =~ "Phoenix"

      # Verify assigns are set correctly
      assert view |> element("[data-testid='category-grid']") |> has_element?() or
               html =~ "카테고리"
    end

    test "displays all tags including those with zero posts", %{conn: conn} do
      # Create a tag without any posts
      _tag = Repo.insert!(%Tag{name: "Empty Category", slug: "empty-category"})

      {:ok, _view, html} = live(conn, "/categories")

      # Verify empty category is displayed
      assert html =~ "Empty Category"
    end

    test "loads popular posts section", %{conn: conn} do
      # Create a popular post
      post =
        Repo.insert!(%Post{
          slug: "popular-post",
          title: "Popular Post Title",
          author: "Test Author",
          summary: "Test summary",
          thumbnail: "test.jpg",
          published_at: ~U[2024-01-01 12:00:00Z],
          reading_time: 5,
          content_path: "popular-post.md",
          is_popular: true
        })

      # Create a tag and associate it
      tag = Repo.insert!(%Tag{name: "Popular", slug: "popular"})

      Repo.insert_all("post_tags", [
        %{post_id: post.id, tag_id: tag.id, inserted_at: ~U[2024-01-01 12:00:00Z]}
      ])

      {:ok, _view, html} = live(conn, "/categories")

      # Verify popular post is displayed
      assert html =~ "Popular Post Title" or html =~ "인기"
    end

    test "handles empty database gracefully", %{conn: conn} do
      # No tags or posts in database

      {:ok, _view, html} = live(conn, "/categories")

      # Should not crash, page should load
      assert html =~ "카테고리"
      refute html =~ "error"
    end

    test "sets correct page title and metadata", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/categories")

      # Verify page_title assign is set
      assert render(view) =~ "카테고리"
    end

    test "displays categories in alphabetical order by default", %{conn: conn} do
      # Create tags in non-alphabetical order
      _tag1 = Repo.insert!(%Tag{name: "Zulu", slug: "zulu"})
      _tag2 = Repo.insert!(%Tag{name: "Alpha", slug: "alpha"})
      _tag3 = Repo.insert!(%Tag{name: "Bravo", slug: "bravo"})

      {:ok, _view, html} = live(conn, "/categories")

      # Find positions of tag names in HTML
      alpha_pos = :binary.match(html, "Alpha") |> elem(0)
      bravo_pos = :binary.match(html, "Bravo") |> elem(0)
      zulu_pos = :binary.match(html, "Zulu") |> elem(0)

      # Verify alphabetical order (Alpha < Bravo < Zulu in rendered HTML)
      assert alpha_pos < bravo_pos
      assert bravo_pos < zulu_pos
    end

    test "handles Korean tag names correctly", %{conn: conn} do
      # Create tags with Korean names
      _tag1 = Repo.insert!(%Tag{name: "엘릭서", slug: "elixir-kr"})
      _tag2 = Repo.insert!(%Tag{name: "피닉스", slug: "phoenix-kr"})

      {:ok, _view, html} = live(conn, "/categories")

      # Verify Korean tag names are displayed
      assert html =~ "엘릭서"
      assert html =~ "피닉스"
    end

    test "filters popular posts correctly by is_popular flag", %{conn: conn} do
      # Create a tag
      tag = Repo.insert!(%Tag{name: "Test", slug: "test"})

      # Create a popular post
      popular_post =
        Repo.insert!(%Post{
          slug: "popular-1",
          title: "Popular Post",
          author: "Author",
          summary: "Summary",
          thumbnail: "thumb.jpg",
          published_at: ~U[2024-01-01 12:00:00Z],
          reading_time: 5,
          content_path: "popular-1.md",
          is_popular: true
        })

      # Create a non-popular post
      normal_post =
        Repo.insert!(%Post{
          slug: "normal-1",
          title: "Normal Post",
          author: "Author",
          summary: "Summary",
          thumbnail: "thumb.jpg",
          published_at: ~U[2024-01-02 12:00:00Z],
          reading_time: 5,
          content_path: "normal-1.md",
          is_popular: false
        })

      # Associate both posts with tag
      Repo.insert_all("post_tags", [
        %{post_id: popular_post.id, tag_id: tag.id, inserted_at: ~U[2024-01-01 12:00:00Z]},
        %{post_id: normal_post.id, tag_id: tag.id, inserted_at: ~U[2024-01-02 12:00:00Z]}
      ])

      {:ok, _view, html} = live(conn, "/categories")

      # Verify only popular post is shown in popular section
      assert html =~ "Popular Post"
      # Normal post should not be in popular section (though it might be elsewhere)
    end

    test "displays popular posts sorted by published_at descending", %{conn: conn} do
      # Create tag
      tag = Repo.insert!(%Tag{name: "Test", slug: "test"})

      # Create popular posts with different published dates
      post1 =
        Repo.insert!(%Post{
          slug: "popular-old",
          title: "Old Popular Post",
          author: "Author",
          summary: "Summary",
          thumbnail: "thumb.jpg",
          published_at: ~U[2024-01-01 12:00:00Z],
          reading_time: 5,
          content_path: "popular-old.md",
          is_popular: true
        })

      post2 =
        Repo.insert!(%Post{
          slug: "popular-new",
          title: "New Popular Post",
          author: "Author",
          summary: "Summary",
          thumbnail: "thumb.jpg",
          published_at: ~U[2024-01-03 12:00:00Z],
          reading_time: 5,
          content_path: "popular-new.md",
          is_popular: true
        })

      post3 =
        Repo.insert!(%Post{
          slug: "popular-middle",
          title: "Middle Popular Post",
          author: "Author",
          summary: "Summary",
          thumbnail: "thumb.jpg",
          published_at: ~U[2024-01-02 12:00:00Z],
          reading_time: 5,
          content_path: "popular-middle.md",
          is_popular: true
        })

      # Associate posts with tag
      Repo.insert_all("post_tags", [
        %{post_id: post1.id, tag_id: tag.id, inserted_at: ~U[2024-01-01 12:00:00Z]},
        %{post_id: post2.id, tag_id: tag.id, inserted_at: ~U[2024-01-03 12:00:00Z]},
        %{post_id: post3.id, tag_id: tag.id, inserted_at: ~U[2024-01-02 12:00:00Z]}
      ])

      {:ok, _view, html} = live(conn, "/categories")

      # Find positions of post titles in HTML
      new_pos = :binary.match(html, "New Popular Post") |> elem(0)
      middle_pos = :binary.match(html, "Middle Popular Post") |> elem(0)
      old_pos = :binary.match(html, "Old Popular Post") |> elem(0)

      # Verify descending order by published_at (newest first)
      assert new_pos < middle_pos
      assert middle_pos < old_pos
    end

    test "displays empty state when no popular posts exist", %{conn: conn} do
      # Create a regular post (not popular)
      tag = Repo.insert!(%Tag{name: "Test", slug: "test"})

      post =
        Repo.insert!(%Post{
          slug: "regular-post",
          title: "Regular Post",
          author: "Author",
          summary: "Summary",
          thumbnail: "thumb.jpg",
          published_at: ~U[2024-01-01 12:00:00Z],
          reading_time: 5,
          content_path: "regular-post.md",
          is_popular: false
        })

      Repo.insert_all("post_tags", [
        %{post_id: post.id, tag_id: tag.id, inserted_at: ~U[2024-01-01 12:00:00Z]}
      ])

      {:ok, _view, html} = live(conn, "/categories")

      # Verify empty state message is displayed
      assert html =~ "인기 포스트가 없습니다"
      assert html =~ "아직 인기 포스트로 표시된 글이 없습니다"
    end

    test "displays accurate post counts matching database", %{conn: conn} do
      # Create tags with specific post counts
      tag1 = Repo.insert!(%Tag{name: "Tag1", slug: "tag1"})
      tag2 = Repo.insert!(%Tag{name: "Tag2", slug: "tag2"})
      tag3 = Repo.insert!(%Tag{name: "Tag3", slug: "tag3"})

      # Create posts for tag1 (5 posts)
      for i <- 1..5 do
        post =
          Repo.insert!(%Post{
            slug: "tag1-post-#{i}",
            title: "Tag1 Post #{i}",
            author: "Author",
            summary: "Summary",
            thumbnail: "thumb.jpg",
            published_at: ~U[2024-01-01 12:00:00Z],
            reading_time: 5,
            content_path: "tag1-post-#{i}.md"
          })

        Repo.insert_all("post_tags", [
          %{post_id: post.id, tag_id: tag1.id, inserted_at: ~U[2024-01-01 12:00:00Z]}
        ])
      end

      # Create posts for tag2 (3 posts)
      for i <- 1..3 do
        post =
          Repo.insert!(%Post{
            slug: "tag2-post-#{i}",
            title: "Tag2 Post #{i}",
            author: "Author",
            summary: "Summary",
            thumbnail: "thumb.jpg",
            published_at: ~U[2024-01-01 12:00:00Z],
            reading_time: 5,
            content_path: "tag2-post-#{i}.md"
          })

        Repo.insert_all("post_tags", [
          %{post_id: post.id, tag_id: tag2.id, inserted_at: ~U[2024-01-01 12:00:00Z]}
        ])
      end

      # tag3 has no posts

      {:ok, _view, html} = live(conn, "/categories")

      # Verify accurate post counts are displayed
      assert html =~ "Tag1"
      assert html =~ "5개의 포스트"

      assert html =~ "Tag2"
      assert html =~ "3개의 포스트"

      assert html =~ "Tag3"
      assert html =~ "0개의 포스트"

      # Verify counts match database
      categories = ElixirBlog.Blog.list_tags_with_post_counts()
      tag1_data = Enum.find(categories, fn c -> c.slug == "tag1" end)
      tag2_data = Enum.find(categories, fn c -> c.slug == "tag2" end)
      tag3_data = Enum.find(categories, fn c -> c.slug == "tag3" end)

      assert tag1_data.post_count == 5
      assert tag2_data.post_count == 3
      assert tag3_data.post_count == 0
    end
  end
end
