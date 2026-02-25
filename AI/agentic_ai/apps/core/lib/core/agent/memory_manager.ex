defmodule Core.Agent.MemoryManager do
  @moduledoc """
  Supervisor 에이전트의 장기 기억을 관리합니다.

  - 대화 요약 저장
  - 학습된 패턴 기록
  - 프로젝트 컨텍스트 관리
  - 성능 메트릭 추적
  - Markdown 파일 동기화
  """

  require Logger
  alias Core.Schema.AgentMemory
  alias Core.Repo
  import Ecto.Query

  @memory_dir "data/memories"
  @user_profile_key "user_profile"

  @doc """
  사용자 프로필 정보를 조회합니다.

  ## Returns

    - `{:ok, profile}` - 프로필이 존재하는 경우
    - `{:error, :not_found}` - 프로필이 없는 경우
  """
  def get_user_profile do
    case Repo.get_by(AgentMemory, memory_type: :project_context, key: @user_profile_key) do
      nil -> {:error, :not_found}
      memory -> {:ok, memory.value}
    end
  end

  @doc """
  사용자 프로필 정보를 저장합니다.

  ## Parameters

    - `profile` - 프로필 정보 맵
      - `:user_name` - 사용자 이름
      - `:agent_name` - 에이전트 이름
      - `:city` - 현재 도시

  ## Examples

      iex> MemoryManager.save_user_profile(%{
      ...>   user_name: "홍길동",
      ...>   agent_name: "AI 비서",
      ...>   city: "서울"
      ...> })
      {:ok, %AgentMemory{}}
  """
  def save_user_profile(profile) do
    # 글로벌 프로필이므로 특정 에이전트에 연결하지 않음
    # 대신 첫 번째 활성 supervisor 에이전트를 사용
    agent = get_default_agent()

    if agent do
      attrs = %{
        agent_id: agent.id,
        memory_type: :project_context,
        key: @user_profile_key,
        value: Map.merge(profile, %{updated_at: DateTime.utc_now() |> DateTime.to_iso8601()}),
        relevance_score: 1.0
      }

      case Repo.get_by(AgentMemory, memory_type: :project_context, key: @user_profile_key) do
        nil ->
          %AgentMemory{}
          |> AgentMemory.changeset(attrs)
          |> Repo.insert()

        existing ->
          existing
          |> AgentMemory.changeset(attrs)
          |> Repo.update()
      end
    else
      {:error, :no_agent_available}
    end
  end

  @doc """
  사용자 프로필이 완전한지 확인합니다.
  """
  def user_profile_complete? do
    case get_user_profile() do
      {:ok, profile} ->
        has_user_name = Map.get(profile, "user_name") || Map.get(profile, :user_name)
        has_agent_name = Map.get(profile, "agent_name") || Map.get(profile, :agent_name)
        has_city = Map.get(profile, "city") || Map.get(profile, :city)

        has_user_name && has_agent_name && has_city

      {:error, _} ->
        false
    end
  end

  defp get_default_agent do
    import Ecto.Query

    from(a in Core.Schema.Agent,
      where: a.type == :supervisor and a.status == :active,
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  메모리를 저장합니다.

  ## Parameters

    - `agent_id` - 에이전트 ID
    - `memory_type` - 메모리 타입 (:conversation_summary, :learned_pattern, :project_context, :performance_metric)
    - `key` - 메모리 키 (예: "user_preferences", "coding_patterns")
    - `value` - 저장할 값 (map)
    - `opts` - 옵션
      - `:metadata` - 추가 메타데이터
      - `:conversation_id` - 연관된 대화 ID
      - `:relevance_score` - 관련성 점수 (0.0 ~ 1.0)
      - `:expires_at` - 만료 시각

  ## Examples

      iex> MemoryManager.store(agent_id, :learned_pattern, "error_handling", %{
      ...>   pattern: "Always log errors before returning",
      ...>   examples: [...]
      ...> })
      {:ok, %AgentMemory{}}
  """
  def store(agent_id, memory_type, key, value, opts \\ []) do
    attrs = %{
      agent_id: agent_id,
      memory_type: memory_type,
      key: key,
      value: value,
      metadata: Keyword.get(opts, :metadata),
      conversation_id: Keyword.get(opts, :conversation_id),
      relevance_score: Keyword.get(opts, :relevance_score),
      expires_at: Keyword.get(opts, :expires_at)
    }

    # Upsert: 존재하면 업데이트, 없으면 삽입
    case get_memory(agent_id, memory_type, key) do
      nil ->
        %AgentMemory{}
        |> AgentMemory.changeset(attrs)
        |> Repo.insert()

      existing ->
        existing
        |> AgentMemory.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  메모리를 검색합니다.

  ## Parameters

    - `agent_id` - 에이전트 ID
    - `memory_type` - 메모리 타입
    - `opts` - 옵션
      - `:key` - 특정 키로 검색
      - `:conversation_id` - 특정 대화와 연관된 메모리만
      - `:limit` - 최대 결과 개수
      - `:min_relevance` - 최소 관련성 점수

  ## Examples

      iex> MemoryManager.retrieve(agent_id, :learned_pattern, key: "error_handling")
      [%AgentMemory{}]
  """
  def retrieve(agent_id, memory_type, opts \\ []) do
    query =
      from(m in AgentMemory,
        where: m.agent_id == ^agent_id and m.memory_type == ^memory_type,
        order_by: [desc: m.relevance_score, desc: m.inserted_at]
      )

    query =
      if key = Keyword.get(opts, :key) do
        from(m in query, where: m.key == ^key)
      else
        query
      end

    query =
      if conversation_id = Keyword.get(opts, :conversation_id) do
        from(m in query, where: m.conversation_id == ^conversation_id)
      else
        query
      end

    query =
      if min_relevance = Keyword.get(opts, :min_relevance) do
        from(m in query, where: m.relevance_score >= ^min_relevance)
      else
        query
      end

    query =
      if limit = Keyword.get(opts, :limit) do
        from(m in query, limit: ^limit)
      else
        query
      end

    # 만료된 메모리 필터링
    query = from(m in query, where: is_nil(m.expires_at) or m.expires_at > ^DateTime.utc_now())

    Repo.all(query)
  end

  @doc """
  특정 타입의 모든 메모리를 조회합니다.
  """
  def list_by_type(agent_id, memory_type) do
    retrieve(agent_id, memory_type)
  end

  @doc """
  메모리를 삭제합니다.
  """
  def delete(agent_id, memory_type, key) do
    case get_memory(agent_id, memory_type, key) do
      nil -> {:error, :not_found}
      memory -> Repo.delete(memory)
    end
  end

  @doc """
  에이전트의 모든 메모리를 Markdown 파일로 내보냅니다.

  파일 위치: `data/memories/{agent_name}/memory.md`
  """
  def export_to_markdown(agent_id) do
    agent = Core.Repo.get(Core.Schema.Agent, agent_id)

    if !agent do
      {:error, :agent_not_found}
    else
      memories_by_type = %{
        conversation_summary: retrieve(agent_id, :conversation_summary),
        learned_pattern: retrieve(agent_id, :learned_pattern),
        project_context: retrieve(agent_id, :project_context),
        performance_metric: retrieve(agent_id, :performance_metric)
      }

      # 사용자 프로필 가져오기
      user_profile =
        case get_user_profile() do
          {:ok, profile} -> profile
          {:error, _} -> nil
        end

      content = build_markdown_content(agent, memories_by_type, user_profile)

      file_path = get_memory_file_path(agent.name)
      File.mkdir_p!(Path.dirname(file_path))

      case File.write(file_path, content) do
        :ok ->
          Logger.info("Exported memories to #{file_path}")
          {:ok, file_path}

        {:error, reason} ->
          Logger.error("Failed to export memories: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Markdown 파일에서 메모리를 가져옵니다.

  ## Parameters

    - `agent_id` - 에이전트 ID
    - `file_path` - Markdown 파일 경로 (선택, 기본값: `data/memories/{agent_name}/memory.md`)
  """
  def import_from_markdown(agent_id, file_path \\ nil) do
    agent = Core.Repo.get(Core.Schema.Agent, agent_id)

    if !agent do
      {:error, :agent_not_found}
    else
      path = file_path || get_memory_file_path(agent.name)

      case File.read(path) do
        {:ok, content} ->
          parse_and_import_markdown(agent_id, content)

        {:error, reason} ->
          Logger.error("Failed to import memories from #{path}: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  # 비공개 함수들

  defp get_memory(agent_id, memory_type, key) do
    Repo.get_by(AgentMemory, agent_id: agent_id, memory_type: memory_type, key: key)
  end

  defp get_memory_file_path(agent_name) do
    Path.join([@memory_dir, agent_name, "memory.md"])
  end

  defp build_markdown_content(agent, memories_by_type, user_profile) do
    """
    # Supervisor Memory: #{agent.name}

    Last updated: #{DateTime.utc_now() |> DateTime.to_string()}

    ## User Profile

    #{format_user_profile(user_profile)}

    ## Conversation Summaries

    #{format_memories(memories_by_type.conversation_summary)}

    ## Learned Patterns

    #{format_memories(memories_by_type.learned_pattern)}

    ## Project Context

    #{format_memories(memories_by_type.project_context)}

    ## Performance Metrics

    #{format_memories(memories_by_type.performance_metric)}
    """
  end

  defp format_user_profile(nil) do
    "_No user profile set yet._"
  end

  defp format_user_profile(profile) when is_map(profile) do
    user_name = Map.get(profile, "user_name") || Map.get(profile, :user_name) || "_Unknown_"
    agent_name = Map.get(profile, "agent_name") || Map.get(profile, :agent_name) || "_Unknown_"
    city = Map.get(profile, "city") || Map.get(profile, :city) || "_Unknown_"

    """
    - **사용자 이름**: #{user_name}
    - **AI 비서 이름**: #{agent_name}
    - **도시**: #{city}
    """
  end

  defp format_memories([]) do
    "_No memories stored yet._"
  end

  defp format_memories(memories) do
    memories
    |> Enum.map(fn memory ->
      relevance =
        if memory.relevance_score, do: " (#{Float.round(memory.relevance_score, 2)})", else: ""

      """
      ### #{memory.key}#{relevance}

      #{format_value(memory.value)}

      #{if memory.metadata, do: "_Metadata: #{inspect(memory.metadata)}_", else: ""}
      """
    end)
    |> Enum.join("\n")
  end

  defp format_value(value) when is_map(value) do
    value
    |> Enum.map(fn {k, v} -> "- **#{k}**: #{inspect(v)}" end)
    |> Enum.join("\n")
  end

  defp format_value(value), do: inspect(value)

  defp parse_and_import_markdown(agent_id, content) do
    # 간단한 파서: 섹션을 추출하고 메모리 생성
    # 기본 구현 - 추후 개선 가능

    # User Profile 섹션 파싱 및 저장
    parse_and_save_user_profile(content)

    sections = %{
      "Conversation Summaries" => :conversation_summary,
      "Learned Patterns" => :learned_pattern,
      "Project Context" => :project_context,
      "Performance Metrics" => :performance_metric
    }

    results =
      Enum.map(sections, fn {section_name, memory_type} ->
        case extract_section(content, section_name) do
          nil ->
            []

          section_content ->
            parse_section_entries(agent_id, memory_type, section_content)
        end
      end)
      |> List.flatten()

    {:ok, results}
  end

  defp parse_and_save_user_profile(content) do
    case extract_section(content, "User Profile") do
      nil ->
        :ok

      section_content ->
        profile = parse_user_profile_section(section_content)

        if map_size(profile) > 0 do
          save_user_profile(profile)
        end
    end
  end

  defp parse_user_profile_section(section_content) do
    # "- **사용자 이름**: 홍길동" 형식 파싱
    patterns = [
      {~r/\*\*사용자 이름\*\*:\s*(.+)/, :user_name},
      {~r/\*\*AI 비서 이름\*\*:\s*(.+)/, :agent_name},
      {~r/\*\*도시\*\*:\s*(.+)/, :city}
    ]

    Enum.reduce(patterns, %{}, fn {regex, key}, acc ->
      case Regex.run(regex, section_content) do
        [_, value] ->
          trimmed = String.trim(value)

          if trimmed != "_Unknown_" do
            Map.put(acc, key, trimmed)
          else
            acc
          end

        _ ->
          acc
      end
    end)
  end

  defp extract_section(content, section_name) do
    case Regex.run(~r/## #{section_name}\n\n(.*?)(?=\n## |\z)/s, content) do
      [_, section_content] -> section_content
      _ -> nil
    end
  end

  defp parse_section_entries(agent_id, memory_type, section_content) do
    # ### 헤더로 항목 추출
    entries = Regex.scan(~r/### (.+?)\n\n(.*?)(?=\n### |\z)/s, section_content)

    Enum.map(entries, fn [_, key, value_text] ->
      # 간단한 값 파싱 - 일단 텍스트로 저장
      value = %{content: String.trim(value_text)}

      case store(agent_id, memory_type, String.trim(key), value) do
        {:ok, memory} -> memory
        {:error, _} -> nil
      end
    end)
    |> Enum.filter(& &1)
  end
end
