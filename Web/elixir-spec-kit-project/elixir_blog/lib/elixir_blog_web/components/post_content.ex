defmodule ElixirBlogWeb.Components.PostContent do
  use Phoenix.Component

  attr :html_content, :string, required: true

  def post_content(assigns) do
    ~H"""
    <article class="prose prose-lg max-w-none">
      <div class="markdown-content" id="post-content">
        {Phoenix.HTML.raw(@html_content)}
      </div>
    </article>
    """
  end
end
