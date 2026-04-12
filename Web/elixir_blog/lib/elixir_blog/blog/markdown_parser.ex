defmodule ElixirBlog.Blog.MarkdownParser do
  @moduledoc """
  Provides functions for parsing Markdown content, generating table of contents,
  and calculating reading time for Korean blog posts.
  """

  alias ElixirBlog.Blog.MarkdownCache

  @doc """
  Converts Markdown text to HTML using Earmark.
  Uses ETS cache to avoid re-parsing the same content.
  Sanitizes HTML output to prevent XSS attacks.

  ## Examples

      iex> MarkdownParser.parse("# Hello\\n\\nThis is a test.")
      {:ok, "<h1>Hello</h1>\\n<p>This is a test.</p>\\n"}
  """
  def parse(markdown_text) when is_binary(markdown_text) do
    # Check cache first
    case MarkdownCache.get(markdown_text) do
      {:ok, cached_html} ->
        {:ok, cached_html}

      :miss ->
        # Cache miss - parse and cache the result
        # Remove frontmatter before parsing
        content_without_frontmatter = remove_frontmatter(markdown_text)

        # Earmark options with security and syntax highlighting
        options = %Earmark.Options{
          code_class_prefix: "language-",
          smartypants: true,
          breaks: false,
          # Prevent javascript: and data: URLs
          pure_links: true
        }

        case Earmark.as_html(content_without_frontmatter, options) do
          {:ok, html, _} ->
            # Sanitize HTML to prevent XSS attacks
            # Allow common markdown elements but strip potentially dangerous content
            sanitized_html = HtmlSanitizeEx.markdown_html(html)
            MarkdownCache.put(markdown_text, sanitized_html)
            {:ok, sanitized_html}

          {:error, _html, errors} ->
            {:error, errors}
        end
    end
  end

  @doc """
  Generates a table of contents from Markdown text.
  Extracts H2 and H3 headings and returns a list of heading structs.

  Returns a list of maps with :level, :text, and :id keys.

  ## Examples

      iex> markdown = "## Introduction\\n\\n### Background\\n\\n## Conclusion"
      iex> MarkdownParser.generate_toc(markdown)
      [
        %{level: 2, text: "Introduction", id: "introduction"},
        %{level: 3, text: "Background", id: "background"},
        %{level: 2, text: "Conclusion", id: "conclusion"}
      ]
  """
  def generate_toc(markdown_text) when is_binary(markdown_text) do
    markdown_text
    |> String.split("\n")
    |> Enum.reduce([], fn line, acc ->
      cond do
        String.starts_with?(line, "### ") ->
          text = String.trim_leading(line, "### ")
          id = slugify(text)
          [%{level: 3, text: text, id: id} | acc]

        String.starts_with?(line, "## ") ->
          text = String.trim_leading(line, "## ")
          id = slugify(text)
          [%{level: 2, text: text, id: id} | acc]

        true ->
          acc
      end
    end)
    |> Enum.reverse()
  end

  @doc """
  Calculates estimated reading time in minutes for Korean text.
  Uses 250 words per minute as the baseline reading speed.

  Counts Korean syllables and words to determine reading time.

  ## Examples

      iex> MarkdownParser.calculate_reading_time("한글 텍스트입니다. " |> String.duplicate(100))
      1
  """
  def calculate_reading_time(markdown_text) when is_binary(markdown_text) do
    # Remove frontmatter
    content = remove_frontmatter(markdown_text)

    # Remove Markdown syntax (headings, links, code blocks, etc.)
    clean_text =
      content
      # Remove code blocks
      |> String.replace(~r/```[\s\S]*?```/, "")
      # Remove inline code
      |> String.replace(~r/`[^`]+`/, "")
      # Remove images
      |> String.replace(~r/!\[.*?\]\(.*?\)/, "")
      # Replace links with text
      |> String.replace(~r/\[([^\]]+)\]\([^\)]+\)/, "\\1")
      # Remove heading markers
      |> String.replace(~r/^\#{1,6}\s+/m, "")
      # Remove formatting markers
      |> String.replace(~r/[*_~`]/, "")

    # Count Korean characters and words
    korean_chars = count_korean_characters(clean_text)
    english_words = count_english_words(clean_text)

    # Korean: ~250 syllables per minute
    # English: ~250 words per minute
    # Combine both for mixed content
    korean_minutes = korean_chars / 250
    english_minutes = english_words / 250

    total_minutes = korean_minutes + english_minutes

    # Minimum 1 minute
    max(ceil(total_minutes), 1)
  end

  # Private helper functions

  defp remove_frontmatter(text) do
    case String.split(text, "---", parts: 3) do
      [_, _, content] -> content
      _ -> text
    end
  end

  defp count_korean_characters(text) do
    text
    |> String.graphemes()
    |> Enum.count(fn char ->
      case String.to_charlist(char) do
        [codepoint] when codepoint >= 0xAC00 and codepoint <= 0xD7A3 -> true
        _ -> false
      end
    end)
  end

  defp count_english_words(text) do
    text
    |> String.split(~r/\s+/)
    |> Enum.count(fn word ->
      String.match?(word, ~r/[a-zA-Z]+/)
    end)
  end

  defp slugify(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^\w\s가-힣-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.trim("-")
  end
end
