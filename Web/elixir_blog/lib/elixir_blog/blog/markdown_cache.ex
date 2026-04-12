defmodule ElixirBlog.Blog.MarkdownCache do
  @moduledoc """
  ETS-based cache for parsed Markdown HTML.
  Caches parsed HTML to avoid re-parsing the same content repeatedly.
  """

  use GenServer

  @table_name :markdown_cache

  ## Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets cached HTML for the given markdown content.
  Returns `{:ok, html}` if found, `:miss` if not cached.
  """
  def get(markdown_content) do
    key = generate_key(markdown_content)

    case :ets.lookup(@table_name, key) do
      [{^key, html}] -> {:ok, html}
      [] -> :miss
    end
  end

  @doc """
  Puts parsed HTML into the cache.
  """
  def put(markdown_content, html) do
    key = generate_key(markdown_content)
    :ets.insert(@table_name, {key, html})
    :ok
  end

  @doc """
  Clears all cached entries.
  """
  def clear do
    :ets.delete_all_objects(@table_name)
    :ok
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    :ets.new(@table_name, [:named_table, :set, :public, read_concurrency: true])
    {:ok, %{}}
  end

  ## Private Functions

  defp generate_key(content) do
    :crypto.hash(:md5, content) |> Base.encode16()
  end
end
