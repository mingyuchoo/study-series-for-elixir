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

  alias Core.Repo
  alias Core.Schema.Agent
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
        files
        |> load_config_files(dir)
        |> collect_load_results()

      {:error, reason} ->
        Logger.warning("설정 디렉토리를 읽을 수 없습니다: #{dir} - #{inspect(reason)}")
        {:error, "디렉토리를 읽을 수 없습니다: #{inspect(reason)}"}
    end
  end

  defp load_config_files(files, dir) do
    files
    |> Enum.filter(&String.ends_with?(&1, ".md"))
    |> Enum.map(fn file -> load_config(Path.join(dir, file)) end)
  end

  defp collect_load_results(results) do
    errors = Enum.filter(results, &match?({:error, _}, &1))

    if Enum.empty?(errors) do
      agents = Enum.map(results, fn {:ok, agent} -> agent end)
      {:ok, agents}
    else
      {:error, errors}
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

  @doc "Parses agent markdown without I/O."
  defdelegate parse_markdown(content), to: AgentDomain.ConfigParser
  defdelegate parse_frontmatter(text), to: AgentDomain.ConfigParser
  defdelegate parse_body(body), to: AgentDomain.ConfigParser
  defdelegate build_agent_attrs(frontmatter, body, file_path), to: AgentDomain.ConfigParser

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
