defmodule AgentDomain.ConfigParser do
  @moduledoc "Pure parsing and validation of agent markdown configuration."

  alias AgentDomain.FrontmatterParser

  @default_agent_avatars %{
    "main_supervisor" => "avatar-01.png",
    "research_worker" => "avatar-02.png",
    "knowledge_worker" => "avatar-03.png",
    "calculator_worker" => "avatar-04.png",
    "restructure_worker" => "avatar-05.png",
    "system_worker" => "avatar-06.png"
  }

  @doc """
  Markdown 내용을 frontmatter와 body로 분리합니다.
  """
  def parse_markdown(content) do
    normalized = String.replace(content, "\r\n", "\n")

    case Regex.run(~r/^---\n(.*?)\n---\n(.*)$/s, normalized) do
      [_, frontmatter, body] ->
        {:ok, parse_frontmatter(frontmatter), String.trim(body)}

      _ ->
        {:error, "Invalid markdown format: frontmatter not found"}
    end
  end

  @doc """
  YAML-like frontmatter를 파싱합니다.
  간단한 key: value 형식만 지원합니다.
  """
  def parse_frontmatter(text) do
    FrontmatterParser.parse(text)
  end

  @doc """
  Markdown body에서 섹션을 추출합니다.
  """
  def parse_body(body) do
    sections = %{
      "system_prompt" => nil,
      "config" => nil,
      "enabled_tools" => []
    }

    # ## 헤딩으로 섹션 분리
    parts = Regex.split(~r/^## /m, body, trim: true)

    Enum.reduce(parts, sections, fn part, acc ->
      cond do
        String.starts_with?(part, "System Prompt") ->
          content = extract_section_content(part)
          Map.put(acc, "system_prompt", content)

        String.starts_with?(part, "Configuration") ->
          content = extract_section_content(part)
          config = parse_json_config(content)
          Map.put(acc, "config", config)

        String.starts_with?(part, "Enabled Tools") ->
          content = extract_section_content(part)
          tools = parse_tools_list(content)
          Map.put(acc, "enabled_tools", tools)

        true ->
          acc
      end
    end)
  end

  defp extract_section_content(section) do
    section
    |> String.split("\n", parts: 2)
    |> List.last()
    |> String.trim()
  end

  defp parse_json_config(content) do
    case Jason.decode(content) do
      {:ok, config} -> config
      {:error, _} -> %{}
    end
  end

  defp parse_tools_list(content) do
    content
    |> String.split("\n", trim: true)
    |> Enum.filter(&String.starts_with?(&1, "-"))
    |> Enum.map(&String.trim_leading(&1, "- "))
    |> Enum.map(&String.trim/1)
  end

  @doc """
  frontmatter와 body를 결합하여 Agent 속성 맵을 생성합니다.
  """
  def build_agent_attrs(frontmatter, body, file_path) do
    body_sections = parse_body(body)

    with {:ok, name} <- required_frontmatter(frontmatter, "name"),
         {:ok, type} <- parse_agent_type(frontmatter["type"]),
         {:ok, status} <- parse_agent_status(frontmatter["status"]) do
      attrs =
        %{
          type: type,
          name: name,
          display_name: frontmatter["display_name"],
          description: frontmatter["description"],
          system_prompt: body_sections["system_prompt"],
          model: frontmatter["model"] || "gpt-5-mini",
          temperature: frontmatter["temperature"] || 1.0,
          max_iterations: frontmatter["max_iterations"] || 10,
          enabled_tools: body_sections["enabled_tools"],
          config: body_sections["config"] || %{},
          status: status,
          created_from_markdown: true,
          markdown_path: file_path
        }
        |> maybe_put(:avatar_path, agent_avatar_path(name, frontmatter))

      {:ok, attrs}
    end
  end

  defp required_frontmatter(frontmatter, key) do
    case frontmatter[key] do
      nil -> {:error, "#{key} is required in frontmatter"}
      "" -> {:error, "#{key} is required in frontmatter"}
      value -> {:ok, value}
    end
  end

  defp parse_agent_type(nil), do: {:ok, :worker}
  defp parse_agent_type("supervisor"), do: {:ok, :supervisor}
  defp parse_agent_type("worker"), do: {:ok, :worker}
  defp parse_agent_type(type), do: {:error, "invalid agent type: #{inspect(type)}"}

  defp parse_agent_status(nil), do: {:ok, :active}
  defp parse_agent_status("active"), do: {:ok, :active}
  defp parse_agent_status("disabled"), do: {:ok, :disabled}
  defp parse_agent_status(status), do: {:error, "invalid agent status: #{inspect(status)}"}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp agent_avatar_path(name, frontmatter) do
    frontmatter["avatar_path"] || frontmatter["avatar"] || Map.get(@default_agent_avatars, name)
  end

end
