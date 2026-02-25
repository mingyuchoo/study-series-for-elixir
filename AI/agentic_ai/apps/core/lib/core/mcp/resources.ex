defmodule Core.MCP.Resources do
  @moduledoc """
  MCP Resources 엔드포인트 구현.

  에이전트 설정 파일들을 MCP Resources로 노출합니다.
  Resources는 AI 애플리케이션에 컨텍스트 정보를 제공하는 데이터 소스입니다.

  ## MCP Resources 명세

  - `resources/list`: 사용 가능한 모든 리소스 목록 반환
  - `resources/read`: 특정 리소스의 내용 반환

  ## 리소스 URI 형식

  - `agent://supervisor/main` - Supervisor 에이전트 설정
  - `agent://worker/general` - General Worker 설정
  - `skill://research-report` - 스킬 정의
  - `config://agents` - 모든 에이전트 목록
  """

  alias Core.MCP.Protocol
  require Logger

  @doc """
  에이전트 설정 디렉토리 경로를 반환합니다.
  """
  def agents_dir do
    Application.get_env(:core, :agents_dir, default_agents_dir())
  end

  @doc """
  스킬 설정 디렉토리 경로를 반환합니다.
  """
  def skills_dir do
    Application.get_env(:core, :skills_dir, default_skills_dir())
  end

  defp default_agents_dir do
    Path.join(project_root(), "config/agents")
  end

  defp default_skills_dir do
    Path.join(project_root(), "config/skills")
  end

  defp project_root do
    # umbrella 프로젝트 루트 찾기
    case File.cwd() do
      {:ok, cwd} ->
        if String.contains?(cwd, "/apps/") do
          # apps/core 또는 apps/web 내부에서 실행 중
          cwd |> Path.join("../..") |> Path.expand()
        else
          cwd
        end

      _ ->
        "."
    end
  end

  @doc """
  모든 리소스 목록을 반환합니다 (resources/list).

  ## Returns

      {:ok, %{"resources" => [...]}}
  """
  def list do
    agent_resources = list_agent_resources()
    skill_resources = list_skill_resources()
    meta_resources = list_meta_resources()

    resources = agent_resources ++ skill_resources ++ meta_resources

    {:ok, %{"resources" => resources}}
  end

  @doc """
  특정 리소스의 내용을 반환합니다 (resources/read).

  ## Parameters

    - `params` - 리소스 읽기 파라미터
      - `"uri"` - 리소스 URI (필수)

  ## Returns

      {:ok, %{"contents" => [%{"uri" => "...", "mimeType" => "...", "text" => "..."}]}}
  """
  def read(%{"uri" => uri}) do
    case parse_uri(uri) do
      {:agent, type, name} ->
        read_agent_resource(type, name, uri)

      {:skill, name} ->
        read_skill_resource(name, uri)

      {:config, "agents"} ->
        read_agents_config(uri)

      {:config, "skills"} ->
        read_skills_config(uri)

      {:error, reason} ->
        {:error, Protocol.invalid_params_error(reason)}
    end
  end

  def read(_params) do
    {:error, Protocol.invalid_params_error("Missing required parameter: uri")}
  end

  # 비공개 함수들 - 목록 조회

  defp list_agent_resources do
    case File.ls(agents_dir()) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".md"))
        |> Enum.map(&build_agent_resource_entry/1)

      {:error, _} ->
        Logger.warning("에이전트 설정 디렉토리를 읽을 수 없습니다: #{agents_dir()}")
        []
    end
  end

  defp list_skill_resources do
    case File.ls(skills_dir()) do
      {:ok, dirs} ->
        dirs
        |> Enum.filter(fn dir ->
          Path.join(skills_dir(), dir) |> File.dir?()
        end)
        |> Enum.map(&build_skill_resource_entry/1)

      {:error, _} ->
        Logger.warning("스킬 디렉토리를 읽을 수 없습니다: #{skills_dir()}")
        []
    end
  end

  defp list_meta_resources do
    [
      %{
        "uri" => "config://agents",
        "name" => "All Agents Configuration",
        "description" => "모든 에이전트 설정 요약",
        "mimeType" => "application/json"
      },
      %{
        "uri" => "config://skills",
        "name" => "All Skills Configuration",
        "description" => "모든 스킬 설정 요약",
        "mimeType" => "application/json"
      }
    ]
  end

  defp build_agent_resource_entry(filename) do
    # supervisor_main.md -> supervisor, main
    name = String.trim_trailing(filename, ".md")
    {type, agent_name} = parse_agent_filename(name)

    %{
      "uri" => "agent://#{type}/#{agent_name}",
      "name" => humanize_name(name),
      "description" => "#{String.capitalize(type)} 에이전트: #{humanize_name(agent_name)}",
      "mimeType" => "text/markdown"
    }
  end

  defp build_skill_resource_entry(dir_name) do
    %{
      "uri" => "skill://#{dir_name}",
      "name" => humanize_name(dir_name),
      "description" => "스킬: #{humanize_name(dir_name)}",
      "mimeType" => "text/markdown"
    }
  end

  defp parse_agent_filename(name) do
    case String.split(name, "_", parts: 2) do
      [type, agent_name] -> {type, agent_name}
      [single] -> {"agent", single}
    end
  end

  # 비공개 함수들 - 읽기

  defp read_agent_resource(type, name, uri) do
    filename = "#{type}_#{name}.md"
    file_path = Path.join(agents_dir(), filename)

    case File.read(file_path) do
      {:ok, content} ->
        {:ok,
         %{
           "contents" => [
             %{
               "uri" => uri,
               "mimeType" => "text/markdown",
               "text" => content
             }
           ]
         }}

      {:error, :enoent} ->
        {:error, Protocol.invalid_params_error("Agent resource not found: #{uri}")}

      {:error, reason} ->
        {:error, Protocol.internal_error("Failed to read resource: #{inspect(reason)}")}
    end
  end

  defp read_skill_resource(name, uri) do
    file_path = Path.join([skills_dir(), name, "SKILL.md"])

    case File.read(file_path) do
      {:ok, content} ->
        {:ok,
         %{
           "contents" => [
             %{
               "uri" => uri,
               "mimeType" => "text/markdown",
               "text" => content
             }
           ]
         }}

      {:error, :enoent} ->
        {:error, Protocol.invalid_params_error("Skill resource not found: #{uri}")}

      {:error, reason} ->
        {:error, Protocol.internal_error("Failed to read resource: #{inspect(reason)}")}
    end
  end

  defp read_agents_config(uri) do
    case File.ls(agents_dir()) do
      {:ok, files} ->
        agents =
          files
          |> Enum.filter(&String.ends_with?(&1, ".md"))
          |> Enum.map(fn filename ->
            name = String.trim_trailing(filename, ".md")
            {type, agent_name} = parse_agent_filename(name)

            %{
              "name" => name,
              "type" => type,
              "agent_name" => agent_name,
              "file" => filename
            }
          end)

        content = Jason.encode!(%{"agents" => agents}, pretty: true)

        {:ok,
         %{
           "contents" => [
             %{
               "uri" => uri,
               "mimeType" => "application/json",
               "text" => content
             }
           ]
         }}

      {:error, reason} ->
        {:error, Protocol.internal_error("Failed to list agents: #{inspect(reason)}")}
    end
  end

  defp read_skills_config(uri) do
    case File.ls(skills_dir()) do
      {:ok, dirs} ->
        skills =
          dirs
          |> Enum.filter(fn dir ->
            Path.join(skills_dir(), dir) |> File.dir?()
          end)
          |> Enum.map(fn dir ->
            skill_file = Path.join([skills_dir(), dir, "SKILL.md"])
            has_skill_file = File.exists?(skill_file)

            %{
              "name" => dir,
              "directory" => dir,
              "has_skill_file" => has_skill_file
            }
          end)

        content = Jason.encode!(%{"skills" => skills}, pretty: true)

        {:ok,
         %{
           "contents" => [
             %{
               "uri" => uri,
               "mimeType" => "application/json",
               "text" => content
             }
           ]
         }}

      {:error, reason} ->
        {:error, Protocol.internal_error("Failed to list skills: #{inspect(reason)}")}
    end
  end

  # 비공개 함수들 - URI 파싱

  defp parse_uri("agent://" <> rest) do
    case String.split(rest, "/", parts: 2) do
      [type, name] -> {:agent, type, name}
      _ -> {:error, "Invalid agent URI format"}
    end
  end

  defp parse_uri("skill://" <> name) do
    if String.length(name) > 0 do
      {:skill, name}
    else
      {:error, "Invalid skill URI format"}
    end
  end

  defp parse_uri("config://" <> name) do
    if name in ["agents", "skills"] do
      {:config, name}
    else
      {:error, "Unknown config resource: #{name}"}
    end
  end

  defp parse_uri(uri) do
    {:error, "Unknown URI scheme: #{uri}"}
  end

  defp humanize_name(name) when is_binary(name) do
    name
    |> String.replace(~r/[-_]/, " ")
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
end
