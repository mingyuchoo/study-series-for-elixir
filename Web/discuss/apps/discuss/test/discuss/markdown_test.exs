defmodule Discuss.MarkdownTest do
  use ExUnit.Case, async: true

  alias Discuss.Markdown

  describe "to_html/1" do
    test "nil을 빈 문자열로 반환한다" do
      assert Markdown.to_html(nil) == ""
    end

    test "빈 문자열을 빈 문자열로 반환한다" do
      assert Markdown.to_html("") == ""
    end

    test "마크다운 헤더를 HTML로 변환한다" do
      assert Markdown.to_html("# 제목") =~ "<h1>"
      assert Markdown.to_html("# 제목") =~ "제목"
    end

    test "마크다운 굵은 글씨를 HTML로 변환한다" do
      assert Markdown.to_html("**굵은 글씨**") =~ "<strong>"
    end

    test "마크다운 리스트를 HTML로 변환한다" do
      result = Markdown.to_html("- 항목1\n- 항목2")
      assert result =~ "<ul>"
      assert result =~ "<li>"
    end

    test "마크다운 코드 블록을 HTML로 변환한다" do
      result = Markdown.to_html("```elixir\nIO.puts(\"hello\")\n```")
      assert result =~ "<code"
    end
  end

  describe "excerpt/2" do
    test "nil을 빈 문자열로 반환한다" do
      assert Markdown.excerpt(nil) == ""
    end

    test "빈 문자열을 빈 문자열로 반환한다" do
      assert Markdown.excerpt("") == ""
    end

    test "HTML 태그를 제거한 plain text를 반환한다" do
      result = Markdown.excerpt("**굵은 글씨**와 일반 텍스트")
      refute result =~ "<strong>"
      assert result =~ "굵은 글씨"
    end

    test "최대 길이를 초과하면 잘라서 반환한다" do
      long_text = String.duplicate("가나다라마바사 ", 50)
      result = Markdown.excerpt(long_text, 20)
      assert String.length(result) <= 23  # 20 + "..."
      assert String.ends_with?(result, "...")
    end

    test "최대 길이 이하면 그대로 반환한다" do
      result = Markdown.excerpt("짧은 텍스트", 200)
      refute String.ends_with?(result, "...")
    end
  end
end
