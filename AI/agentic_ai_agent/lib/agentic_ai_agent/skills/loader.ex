defmodule AgenticAiAgent.Skills.Loader do
  @moduledoc """
  Reads `priv/skills/<slug>/SKILL.md` files. Each file is plain markdown
  with an optional YAML frontmatter block delimited by `---`.

      ---
      name: weather_briefing
      description: Compose a multi-day weather briefing for a city.
      version: 0.1.0
      tools_used: [web_search, http_fetch]
      ---

      # Weather Briefing

      Step 1. Search for ...

  Only the frontmatter is consulted for indexing/matching; the body is
  loaded on demand into a sub-agent's system prompt.
  """

  @type skill :: %{
          slug: String.t(),
          path: String.t(),
          name: String.t(),
          description: String.t(),
          frontmatter: map(),
          body: String.t()
        }

  @spec load_all() :: [skill()]
  def load_all do
    skills_dir = Application.app_dir(:agentic_ai_agent, "priv/skills")

    case File.ls(skills_dir) do
      {:ok, entries} ->
        entries
        |> Enum.map(&Path.join(skills_dir, &1))
        |> Enum.filter(&File.dir?/1)
        |> Enum.map(&Path.join(&1, "SKILL.md"))
        |> Enum.filter(&File.exists?/1)
        |> Enum.map(&load_one/1)
        |> Enum.reject(&is_nil/1)

      {:error, :enoent} ->
        []
    end
  end

  defp load_one(path) do
    slug = path |> Path.dirname() |> Path.basename()

    with {:ok, raw} <- File.read(path),
         {fm, body} <- parse_frontmatter(raw) do
      %{
        slug: slug,
        path: path,
        name: Map.get(fm, "name", slug),
        description: Map.get(fm, "description", ""),
        frontmatter: fm,
        body: body
      }
    else
      _ -> nil
    end
  end

  defp parse_frontmatter("---\n" <> rest) do
    case String.split(rest, "\n---", parts: 2) do
      [yaml, body] ->
        fm =
          case YamlElixir.read_from_string(yaml) do
            {:ok, m} when is_map(m) -> m
            _ -> %{}
          end

        {fm, String.trim_leading(body, "\n")}

      _ ->
        {%{}, rest}
    end
  end

  defp parse_frontmatter(body), do: {%{}, body}
end
