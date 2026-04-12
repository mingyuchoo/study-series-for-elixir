defmodule ElixirBlog.Blog.MarkdownParserTest do
  use ExUnit.Case, async: true

  alias ElixirBlog.Blog.MarkdownParser

  describe "parse/1" do
    test "converts simple markdown heading to HTML" do
      markdown = "# Hello World"
      {:ok, html} = MarkdownParser.parse(markdown)
      assert html =~ "<h1>"
      assert html =~ "Hello World"
      assert html =~ "</h1>"
    end

    test "converts paragraph to HTML" do
      markdown = "This is a paragraph."
      {:ok, html} = MarkdownParser.parse(markdown)
      assert html =~ "<p>"
      assert html =~ "This is a paragraph."
      assert html =~ "</p>"
    end

    test "converts list to HTML" do
      markdown = """
      - Item 1
      - Item 2
      - Item 3
      """

      {:ok, html} = MarkdownParser.parse(markdown)
      assert html =~ "<ul>"
      assert html =~ "Item 1"
      assert html =~ "Item 2"
      assert html =~ "Item 3"
      assert html =~ "</ul>"
    end

    test "converts code block with language to HTML" do
      markdown = """
      ```elixir
      def hello do
        "world"
      end
      ```
      """

      {:ok, html} = MarkdownParser.parse(markdown)
      assert html =~ "<pre>"
      assert html =~ "<code"
      assert html =~ "language-elixir"
    end

    test "handles Korean text correctly" do
      markdown = "# 안녕하세요\n\n이것은 Elixir 테스트입니다."
      {:ok, html} = MarkdownParser.parse(markdown)
      assert html =~ "안녕하세요"
      assert html =~ "이것은 Elixir 테스트입니다."
    end

    test "removes frontmatter before parsing" do
      markdown = """
      ---
      title: Test Post
      author: Test Author
      ---

      # Content
      This is the actual content.
      """

      {:ok, html} = MarkdownParser.parse(markdown)
      refute html =~ "title:"
      refute html =~ "author:"
      assert html =~ "Content"
      assert html =~ "This is the actual content."
    end

    test "sanitizes potentially dangerous HTML" do
      markdown = """
      <script>alert('XSS')</script>

      [Click me](javascript:alert('XSS'))
      """

      {:ok, html} = MarkdownParser.parse(markdown)
      # HtmlSanitizeEx should strip script tags
      refute html =~ "<script>"
      # javascript: URLs should be blocked by pure_links option
      refute html =~ ~s(href="javascript:)
    end

    test "handles very long markdown without crashing" do
      # Earmark is generally tolerant, but we ensure parse doesn't crash
      markdown = String.duplicate("[", 1000)
      result = MarkdownParser.parse(markdown)
      # Should return either ok or error tuple, not crash
      assert match?({:ok, _html}, result) or match?({:error, _errors}, result)
    end
  end

  describe "generate_toc/1" do
    test "extracts H2 headings" do
      markdown = """
      # H1 Title

      ## Introduction
      Some content

      ## Conclusion
      More content
      """

      toc = MarkdownParser.generate_toc(markdown)
      assert length(toc) == 2
      assert %{level: 2, text: "Introduction", id: "introduction"} in toc
      assert %{level: 2, text: "Conclusion", id: "conclusion"} in toc
    end

    test "extracts H3 headings" do
      markdown = """
      ## Main Section

      ### Subsection 1
      ### Subsection 2
      """

      toc = MarkdownParser.generate_toc(markdown)
      assert length(toc) == 3
      assert %{level: 2, text: "Main Section", id: "main-section"} in toc
      assert %{level: 3, text: "Subsection 1", id: "subsection-1"} in toc
      assert %{level: 3, text: "Subsection 2", id: "subsection-2"} in toc
    end

    test "generates slugs for Korean headings" do
      markdown = """
      ## 소개
      ### 배경 설명
      """

      toc = MarkdownParser.generate_toc(markdown)
      assert length(toc) == 2
      assert %{level: 2, text: "소개", id: "소개"} in toc
      assert %{level: 3, text: "배경 설명", id: "배경-설명"} in toc
    end

    test "returns empty list when no headings" do
      markdown = "This is just a paragraph with no headings."
      toc = MarkdownParser.generate_toc(markdown)
      assert toc == []
    end

    test "maintains heading order" do
      markdown = """
      ## First
      ### First Sub
      ## Second
      ### Second Sub
      """

      toc = MarkdownParser.generate_toc(markdown)
      assert length(toc) == 4

      [first, first_sub, second, second_sub] = toc
      assert first.text == "First"
      assert first_sub.text == "First Sub"
      assert second.text == "Second"
      assert second_sub.text == "Second Sub"
    end
  end

  describe "calculate_reading_time/1" do
    test "calculates reading time for Korean text" do
      # Approximately 250 Korean characters should be ~1 minute
      korean_text = String.duplicate("한글", 125)
      reading_time = MarkdownParser.calculate_reading_time(korean_text)
      assert reading_time == 1
    end

    test "calculates reading time for English text" do
      # Approximately 250 English words should be ~1 minute
      english_text = String.duplicate("word ", 250)
      reading_time = MarkdownParser.calculate_reading_time(english_text)
      assert reading_time == 1
    end

    test "calculates reading time for mixed Korean and English" do
      mixed_text = """
      #{String.duplicate("한글", 50)}
      #{String.duplicate("word ", 100)}
      """

      reading_time = MarkdownParser.calculate_reading_time(mixed_text)
      assert reading_time >= 1
    end

    test "returns minimum 1 minute for short text" do
      short_text = "Short text"
      reading_time = MarkdownParser.calculate_reading_time(short_text)
      assert reading_time == 1
    end

    test "ignores code blocks in reading time" do
      markdown = """
      Some text before.

      ```elixir
      #{String.duplicate("code ", 1000)}
      ```

      Some text after.
      """

      reading_time = MarkdownParser.calculate_reading_time(markdown)
      # Should not count the code block
      assert reading_time < 5
    end

    test "ignores frontmatter in reading time" do
      markdown = """
      ---
      title: Test
      author: Test Author
      tags: [elixir, phoenix]
      ---

      #{String.duplicate("word ", 100)}
      """

      reading_time = MarkdownParser.calculate_reading_time(markdown)
      # Should not count frontmatter
      assert reading_time <= 1
    end

    test "removes markdown syntax before counting" do
      markdown = """
      # Heading
      **Bold text**
      *Italic text*
      [Link](http://example.com)
      ![Image](image.jpg)
      """

      reading_time = MarkdownParser.calculate_reading_time(markdown)
      assert reading_time == 1
    end
  end
end
