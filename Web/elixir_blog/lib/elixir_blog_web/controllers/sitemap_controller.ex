defmodule ElixirBlogWeb.SitemapController do
  use ElixirBlogWeb, :controller

  alias ElixirBlog.Blog

  def index(conn, _params) do
    # Get all published posts
    posts = Blog.list_all_posts()

    # Get base URL from endpoint configuration
    base_url = ElixirBlogWeb.Endpoint.url()

    # Build sitemap XML
    sitemap_xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
      <!-- Homepage -->
      <url>
        <loc>#{base_url}/</loc>
        <changefreq>daily</changefreq>
        <priority>1.0</priority>
      </url>

      <!-- Blog Posts -->
    #{Enum.map(posts, fn post -> build_post_url(base_url, post) end) |> Enum.join("\n")}

      <!-- Category Pages -->
    #{build_category_urls(base_url)}
    </urlset>
    """

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, sitemap_xml)
  end

  defp build_post_url(base_url, post) do
    """
      <url>
        <loc>#{base_url}/posts/#{post.slug}</loc>
        <lastmod>#{format_date(post.updated_at || post.inserted_at)}</lastmod>
        <changefreq>monthly</changefreq>
        <priority>0.8</priority>
      </url>
    """
  end

  defp build_category_urls(base_url) do
    tags = Blog.list_tags()

    Enum.map(tags, fn tag ->
      """
        <url>
          <loc>#{base_url}/categories/#{tag.slug}</loc>
          <changefreq>weekly</changefreq>
          <priority>0.6</priority>
        </url>
      """
    end)
    |> Enum.join("\n")
  end

  defp format_date(%DateTime{} = datetime) do
    DateTime.to_iso8601(datetime)
  end

  defp format_date(%NaiveDateTime{} = datetime) do
    NaiveDateTime.to_iso8601(datetime)
  end

  defp format_date(_), do: DateTime.to_iso8601(DateTime.utc_now())
end
