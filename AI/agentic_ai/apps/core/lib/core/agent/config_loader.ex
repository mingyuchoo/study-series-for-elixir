defmodule Core.Agent.ConfigLoader do
  @moduledoc """
  Markdown 형식의 에이전트 설정 파일을 로드하고 데이터베이스에 동기화합니다.

  ## 파일 형식

      ---
      type: supervisor
      name: main_supervisor
      model: gpt-5-mini
      temperature: 1.0
      ---

      # Supervisor Agent: Main

      ## System Prompt
      당신은 사용자 요청을 분석하고...

      ## Configuration
      {"max_concurrent_tasks": 3}

      ## Enabled Tools
      - calculator
      - web_search
  """

  alias Core.Schema.Agent
  alias Core.Repo
  require Logger

  @config_dir "config/agents"

  @doc """
  지정된 디렉토리의 모든 에이전트 설정 파일을 로드합니다.

  ## Examples

      iex> Core.Agent.ConfigLoader.load_all_configs()
      {:ok, [%Agent{}, %Agent{}]}
  """
  def load_all_configs(dir \\ @config_dir) do
    case File.ls(dir) do
      {:ok, files} ->
        results =
          files
          |> Enum.filter(&String.ends_with?(&1, ".md"))
          |> Enum.map(fn file ->
            path = Path.join(dir, file)
            load_config(path)
          end)

        errors = Enum.filter(results, &match?({:error, _}, &1))

        if Enum.empty?(errors) do
          agents = Enum.map(results, fn {:ok, agent} -> agent end)
          {:ok, agents}
        else
          {:error, errors}
        end

      {:error, reason} ->
        Logger.warning("설정 디렉토리를 읽을 수 없습니다: #{dir} - #{inspect(reason)}")
        {:error, "디렉토리를 읽을 수 없습니다: #{inspect(reason)}"}
    end
  end

  @doc """
  단일 Markdown 파일에서 에이전트 설정을 로드하고 DB에 저장합니다.

  ## Examples

      iex> Core.Agent.ConfigLoader.load_config("config/agents/supervisor_main.md")
      {:ok, %Agent{}}
  """
  def load_config(file_path) do
    with {:ok, content} <- File.read(file_path),
         {:ok, frontmatter, body} <- parse_markdown(content),
         {:ok, agent_attrs} <- build_agent_attrs(frontmatter, body, file_path),
         {:ok, agent} <- upsert_agent(agent_attrs) do
      Logger.info("에이전트 설정 로드 완료: #{agent.name}")
      {:ok, agent}
    else
      {:error, reason} ->
        Logger.error("설정 파일 로드 실패: #{file_path} - #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Markdown 내용을 frontmatter와 body로 분리합니다.
  """
  def parse_markdown(content) do
    case Regex.run(~r/^---\n(.*?)\n---\n(.*)$/s, content) do
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
    text
    |> String.split("\n", trim: true)
    |> Enum.reduce(%{}, fn line, acc ->
      case String.split(line, ":", parts: 2) do
        [key, value] ->
          key = String.trim(key)
          value = String.trim(value)
          Map.put(acc, key, parse_value(value))

        _ ->
          acc
      end
    end)
  end

  # 비공개 함수들
  # 값을 적절한 타입으로 변환
  defp parse_value(value) do
    cond do
      value =~ ~r/^\d+\.\d+$/ -> String.to_float(value)
      value =~ ~r/^\d+$/ -> String.to_integer(value)
      value in ["true", "false"] -> value == "true"
      true -> value
    end
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

    attrs = %{
      type: parse_agent_type(frontmatter["type"]),
      name: frontmatter["name"],
      display_name: frontmatter["display_name"],
      description: frontmatter["description"],
      system_prompt: body_sections["system_prompt"],
      model: frontmatter["model"] || "gpt-5-mini",
      temperature: frontmatter["temperature"] || 1.0,
      max_iterations: frontmatter["max_iterations"] || 10,
      enabled_tools: body_sections["enabled_tools"],
      config: body_sections["config"] || %{},
      status: parse_agent_status(frontmatter["status"]),
      created_from_markdown: true,
      markdown_path: file_path
    }

    if attrs.name do
      {:ok, attrs}
    else
      {:error, "name is required in frontmatter"}
    end
  end

  defp parse_agent_type("supervisor"), do: :supervisor
  defp parse_agent_type("worker"), do: :worker
  defp parse_agent_type(_), do: :worker

  defp parse_agent_status("active"), do: :active
  defp parse_agent_status("disabled"), do: :disabled
  defp parse_agent_status(_), do: :active

  @doc """
  에이전트를 DB에 저장하거나 업데이트합니다.
  name을 기준으로 upsert를 수행합니다.
  """
  def upsert_agent(attrs) do
    case Repo.get_by(Agent, name: attrs.name) do
      nil ->
        %Agent{}
        |> Agent.changeset(attrs)
        |> Repo.insert()

      existing ->
        existing
        |> Agent.changeset(attrs)
        |> Repo.update()
    end
  end
end
