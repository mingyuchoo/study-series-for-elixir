defmodule Discuss.Markdown do
  @moduledoc """
  마크다운 텍스트를 HTML로 변환하고, plain text 발췌를 생성하는 헬퍼 모듈.
  """

  @doc """
  마크다운 문자열을 안전한 HTML로 변환한다.
  nil이나 빈 문자열을 안전하게 처리한다.
  """
  def to_html(nil), do: ""
  def to_html(""), do: ""

  def to_html(markdown) when is_binary(markdown) do
    markdown
    |> Earmark.as_html!(compact_output: true)
  end

  @doc """
  마크다운에서 HTML 태그를 제거한 plain text 발췌를 생성한다.

  ## 옵션
    - `max_length` - 최대 문자 수 (기본값: 200)
  """
  def excerpt(markdown, max_length \\ 200)
  def excerpt(nil, _max_length), do: ""
  def excerpt("", _max_length), do: ""

  def excerpt(markdown, max_length) when is_binary(markdown) do
    markdown
    |> to_html()
    |> strip_tags()
    |> String.trim()
    |> truncate(max_length)
  end

  defp strip_tags(html) do
    Regex.replace(~r/<[^>]*>/, html, "")
  end

  defp truncate(text, max_length) when byte_size(text) <= max_length, do: text

  defp truncate(text, max_length) do
    String.slice(text, 0, max_length) <> "..."
  end
end
