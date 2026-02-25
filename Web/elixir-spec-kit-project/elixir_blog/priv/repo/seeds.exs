# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     ElixirBlog.Repo.insert!(%ElixirBlog.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias ElixirBlog.Repo
alias ElixirBlog.Blog
alias ElixirBlog.Blog.{Post, Tag}

# Helper function to parse frontmatter from Markdown files
defmodule SeedHelper do
  def parse_markdown_file(file_path) do
    content = File.read!(file_path)

    case String.split(content, "---", parts: 3) do
      [_, frontmatter, body] ->
        metadata = YamlElixir.read_from_string!(frontmatter)
        slug = extract_slug_from_filename(file_path)

        %{
          slug: slug,
          title: metadata["title"],
          author: metadata["author"],
          summary: metadata["summary"],
          thumbnail: metadata["thumbnail"],
          published_at: parse_datetime(metadata["published_at"]),
          is_popular: metadata["is_popular"] || false,
          tags: metadata["tags"] || [],
          content_path: Path.basename(file_path),
          reading_time: calculate_reading_time(body)
        }

      _ ->
        nil
    end
  end

  defp extract_slug_from_filename(file_path) do
    file_path
    |> Path.basename(".md")
    |> String.replace(~r/^\d{4}-\d{2}-\d{2}-/, "")
  end

  defp parse_datetime(datetime_string) do
    case DateTime.from_iso8601(datetime_string) do
      {:ok, datetime, _} -> DateTime.truncate(datetime, :second)
      _ -> DateTime.utc_now()
    end
  end

  defp calculate_reading_time(content) do
    ElixirBlog.Blog.MarkdownParser.calculate_reading_time(content)
  end
end

# Clear existing data
IO.puts("Clearing existing data...")
Repo.delete_all(Post)
Repo.delete_all(Tag)

# Parse and insert Markdown files
IO.puts("Parsing Markdown files...")
posts_dir = Path.join(:code.priv_dir(:elixir_blog), "posts")

if File.exists?(posts_dir) do
  posts_dir
  |> File.ls!()
  |> Enum.filter(&String.ends_with?(&1, ".md"))
  |> Enum.each(fn filename ->
    file_path = Path.join(posts_dir, filename)
    IO.puts("Processing #{filename}...")

    case SeedHelper.parse_markdown_file(file_path) do
      nil ->
        IO.puts("  Skipped: Invalid frontmatter")

      post_data ->
        # Create or get tags
        tags =
          Enum.map(post_data.tags, fn tag_name ->
            slug = String.downcase(tag_name) |> String.replace(" ", "-")
            {:ok, tag} = Blog.get_or_create_tag(tag_name, slug)
            tag
          end)

        # Create post with associated tags
        {:ok, post} =
          %Post{}
          |> Post.changeset(Map.drop(post_data, [:tags]))
          |> Ecto.Changeset.put_assoc(:tags, tags)
          |> Repo.insert()

        IO.puts("  Created: #{post_data.title}")
    end
  end)
end

# Generate additional sample posts to reach 50
IO.puts("\nGenerating additional sample posts...")

sample_topics = [
  {"Ecto 쿼리 최적화하기", "backend", ["elixir", "ecto", "database"]},
  {"GenServer로 상태 관리하기", "backend", ["elixir", "genserver", "otp"]},
  {"Phoenix 인증 시스템 구축하기", "security", ["phoenix", "authentication", "security"]},
  {"Elixir 테스트 작성 가이드", "testing", ["elixir", "testing", "exunit"]},
  {"LiveView 컴포넌트 패턴", "frontend", ["phoenix", "liveview", "components"]},
  {"Elixir 배포 전략", "devops", ["elixir", "deployment", "docker"]},
  {"OTP 감독 트리 설계", "backend", ["elixir", "otp", "supervision"]},
  {"Phoenix Channels 실시간 통신", "realtime", ["phoenix", "channels", "websocket"]},
  {"Elixir 메타프로그래밍", "advanced", ["elixir", "metaprogramming", "macros"]},
  {"Ecto 다중 데이터베이스 연결", "database", ["ecto", "database", "postgres"]}
]

authors = ["김철수", "이영희", "박민수", "최지은", "정다은"]

current_count = Repo.aggregate(Post, :count)
needed = max(50 - current_count, 0)

1..needed
|> Enum.each(fn i ->
  topic_index = rem(i - 1, length(sample_topics))
  {title_base, category, tag_names} = Enum.at(sample_topics, topic_index)

  author = Enum.random(authors)

  date =
    DateTime.utc_now()
    |> DateTime.add(-:rand.uniform(180), :day)
    |> DateTime.truncate(:second)

  slug = "#{category}-post-#{i}"
  title = "#{title_base} #{i}부"

  # Create tags
  tags =
    Enum.map(tag_names, fn tag_name ->
      tag_slug = String.downcase(tag_name) |> String.replace(" ", "-")
      {:ok, tag} = Blog.get_or_create_tag(tag_name, tag_slug)
      tag
    end)

  # Create post with generated content and associated tags
  {:ok, post} =
    %Post{}
    |> Post.changeset(%{
      slug: slug,
      title: title,
      author: author,
      summary: "#{title}에 대한 상세한 설명입니다. 실전 예제와 함께 알아봅니다.",
      thumbnail: "/images/thumbnails/default.jpg",
      published_at: date,
      is_popular: :rand.uniform() > 0.8,
      reading_time: :rand.uniform(15) + 3,
      content_path: "generated-#{slug}.md"
    })
    |> Ecto.Changeset.put_assoc(:tags, tags)
    |> Repo.insert()

  if rem(i, 10) == 0 do
    IO.puts("  Generated #{i} posts...")
  end
end)

final_count = Repo.aggregate(Post, :count)
tag_count = Repo.aggregate(Tag, :count)

IO.puts("\n✓ Seeding complete!")
IO.puts("  Posts: #{final_count}")
IO.puts("  Tags: #{tag_count}")
