defmodule Core.Agent.SkillRegistry do
  @moduledoc """
  스킬 파일을 로드하고 관리하는 레지스트리.

  스킬(Skill)은 도구(Tool)와 달리 API가 아닌 지식입니다.
  에이전트에게 기존 도구들을 조합하여 복잡한 워크플로우를 수행하는 방법을 가르칭니다.

  Agent Skills 명세(https://agentskills.io/specification)를 따릅니다.

  ## 스킬 디렉토리 구조

      config/skills/
      ├── research-report/
      │   └── SKILL.md
      └── code-analysis/
          └── SKILL.md

  ## 스킬 파일 형식 (SKILL.md)

  Agent Skills 명세에 따른 YAML frontmatter:

      ---
      name: research-report
      description: 웹 검색을 통해 정보를 수집하고 보고서를 작성합니다.
      metadata:
        display-name: Research Report Generator
        required-tools: search_web write_file
        status: active
      ---

      # Skill: Research Report Generator

      ## Workflow
      ...

  ### 필수 필드

    - `name` - 스킬 이름
      - 1-64자
      - 소문자, 숫자, 하이픈만 허용 (a-z, 0-9, -)
      - 하이픈으로 시작/끝 불가
      - 연속 하이픈(--) 불가
      - 부모 디렉토리명과 일치 필수
    - `description` - 스킬 설명 (1-1024자, 언제 사용하는지 포함)

  ### 선택 필드

    - `license` - 라이선스 (Apache-2.0 등)
    - `compatibility` - 환경 요구사항 (최대 500자)
    - `allowed-tools` - 사전 승인된 도구 목록 (space-delimited, 실험적)
    - `metadata` - 추가 메타데이터 (display-name, author, version 등)

  ## 사용 예시

      # 모든 스킬 로드
      {:ok, skills} = SkillRegistry.load_all_skills()

      # 특정 스킬 조회
      skill = SkillRegistry.get_skill("research-report")

      # 에이전트가 사용 가능한 스킬 필터링
      available = SkillRegistry.get_available_skills(["search_web", "write_file"])

      # 스킬을 시스템 프롬프트 형태로 변환
      prompt = SkillRegistry.build_skill_prompt(skills)
  """

  use GenServer
  require Logger

  @skills_dir "config/skills"

  # 클라이언트 API

  @doc """
  SkillRegistry를 시작합니다.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  모든 스킬을 로드합니다.
  """
  def load_all_skills(dir \\ @skills_dir) do
    GenServer.call(__MODULE__, {:load_all, dir})
  end

  @doc """
  이름으로 스킬을 조회합니다.
  """
  def get_skill(name) do
    GenServer.call(__MODULE__, {:get, name})
  end

  @doc """
  모든 스킬 목록을 반환합니다.
  """
  def get_all_skills do
    GenServer.call(__MODULE__, :get_all)
  end

  @doc """
  에이전트가 활성화한 도구들로 사용 가능한 스킬만 필터링합니다.

  ## Parameters

    - `enabled_tools` - 에이전트가 활성화한 도구 이름 목록

  ## Returns

    사용 가능한 스킬 목록 (required_tools가 모두 enabled_tools에 포함된 스킬)
  """
  def get_available_skills(enabled_tools) when is_list(enabled_tools) do
    GenServer.call(__MODULE__, {:get_available, enabled_tools})
  end

  @doc """
  스킬 목록을 시스템 프롬프트에 주입할 형태로 변환합니다.

  ## Returns

    마크다운 형식의 스킬 가이드 문자열
  """
  def build_skill_prompt(skills) when is_list(skills) do
    if Enum.empty?(skills) do
      ""
    else
      skill_sections =
        skills
        |> Enum.map(&format_skill_for_prompt/1)
        |> Enum.join("\n\n---\n\n")

      """
      ## 사용 가능한 스킬 (워크플로우 레시피)

      다음 스킬들은 도구들을 조합하여 복잡한 작업을 수행하는 방법을 안내합니다.
      사용자의 요청에 따라 적절한 스킬을 선택하고, 해당 워크플로우를 따라 작업을 수행하세요.

      #{skill_sections}
      """
    end
  end

  # 서버 콜백

  @impl true
  def init(_opts) do
    state = %{
      skills: %{},
      loaded: false
    }

    # 시작 시 스킬 자동 로드
    send(self(), :load_skills)

    {:ok, state}
  end

  @impl true
  def handle_info(:load_skills, state) do
    case do_load_all(@skills_dir) do
      {:ok, skills_map} ->
        Logger.info("스킬 #{map_size(skills_map)}개 로드 완료")
        {:noreply, %{state | skills: skills_map, loaded: true}}

      {:error, reason} ->
        Logger.warning("스킬 로드 실패: #{inspect(reason)}")
        {:noreply, %{state | loaded: true}}
    end
  end

  @impl true
  def handle_call({:load_all, dir}, _from, state) do
    case do_load_all(dir) do
      {:ok, skills_map} ->
        Logger.info("스킬 #{map_size(skills_map)}개 로드 완료")
        {:reply, {:ok, Map.values(skills_map)}, %{state | skills: skills_map, loaded: true}}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:get, name}, _from, state) do
    {:reply, Map.get(state.skills, name), state}
  end

  @impl true
  def handle_call(:get_all, _from, state) do
    {:reply, Map.values(state.skills), state}
  end

  @impl true
  def handle_call({:get_available, enabled_tools}, _from, state) do
    available =
      state.skills
      |> Map.values()
      |> Enum.filter(fn skill ->
        skill.status == :active &&
          Enum.all?(skill.allowed_tools, &(&1 in enabled_tools))
      end)

    {:reply, available, state}
  end

  # 비공개 함수들

  defp do_load_all(dir) do
    case File.ls(dir) do
      {:ok, entries} ->
        skills =
          entries
          |> Enum.filter(fn entry ->
            Path.join(dir, entry) |> File.dir?()
          end)
          |> Enum.reduce(%{}, fn subdir, acc ->
            skill_file = Path.join([dir, subdir, "SKILL.md"])

            case load_skill(skill_file) do
              {:ok, skill} ->
                Map.put(acc, skill.name, skill)

              {:error, reason} ->
                Logger.warning("스킬 로드 실패: #{skill_file} - #{inspect(reason)}")
                acc
            end
          end)

        {:ok, skills}

      {:error, :enoent} ->
        Logger.info("스킬 디렉토리가 없습니다: #{dir}")
        {:ok, %{}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp load_skill(file_path) do
    dir_name = file_path |> Path.dirname() |> Path.basename()

    with {:ok, content} <- File.read(file_path),
         {:ok, frontmatter, body} <- parse_markdown(content),
         :ok <- validate_name(frontmatter["name"], dir_name),
         :ok <- validate_description(frontmatter["description"]),
         :ok <- validate_compatibility(frontmatter["compatibility"]) do
      metadata = frontmatter["metadata"] || %{}

      # allowed-tools: 명세에 따라 최상위 필드 우선, metadata 내부는 하위 호환성
      allowed_tools =
        parse_allowed_tools(frontmatter["allowed-tools"]) ||
          parse_allowed_tools(metadata["required-tools"]) ||
          []

      skill = %{
        name: frontmatter["name"],
        display_name: metadata["display-name"] || frontmatter["name"],
        description: frontmatter["description"] || "",
        # 명세 표준: allowed-tools (사전 승인 도구)
        allowed_tools: allowed_tools,
        # 하위 호환성: required_tools (기존 코드와 호환)
        required_tools: allowed_tools,
        license: frontmatter["license"],
        compatibility: frontmatter["compatibility"],
        status: parse_status(metadata["status"]),
        metadata: metadata,
        workflow: extract_workflow(body),
        examples: extract_examples(body),
        full_content: body
      }

      {:ok, skill}
    end
  end

  defp parse_markdown(content) do
    case Regex.run(~r/^---\n(.*?)\n---\n(.*)$/s, content) do
      [_, frontmatter, body] ->
        {:ok, parse_frontmatter(frontmatter), String.trim(body)}

      _ ->
        {:error, "Invalid markdown format"}
    end
  end

  defp parse_frontmatter(text) do
    text
    |> String.split("\n")
    |> parse_yaml_lines(%{}, nil, nil)
  end

  # 간단한 YAML 파서 (리스트 및 중첩 지원)
  defp parse_yaml_lines([], acc, _current_list_key, _current_map_key), do: acc

  defp parse_yaml_lines([line | rest], acc, current_list_key, current_map_key) do
    trimmed = String.trim(line)
    indent = get_indent(line)

    cond do
      # 빈 줄
      trimmed == "" ->
        parse_yaml_lines(rest, acc, current_list_key, current_map_key)

      # 리스트 항목 (들여쓰기 있음)
      String.starts_with?(trimmed, "- ") ->
        value = String.trim_leading(trimmed, "- ")

        if current_list_key do
          current_list = Map.get(acc, current_list_key, [])
          acc = Map.put(acc, current_list_key, current_list ++ [value])
          parse_yaml_lines(rest, acc, current_list_key, nil)
        else
          parse_yaml_lines(rest, acc, nil, nil)
        end

      # 중첩된 key: value (들여쓰기 있음)
      indent > 0 and current_map_key != nil ->
        case String.split(trimmed, ":", parts: 2) do
          [key, value] ->
            key = String.trim(key)
            value = String.trim(value)
            current_map = Map.get(acc, current_map_key, %{})
            updated_map = Map.put(current_map, key, parse_value(value))
            acc = Map.put(acc, current_map_key, updated_map)
            parse_yaml_lines(rest, acc, nil, current_map_key)

          _ ->
            parse_yaml_lines(rest, acc, current_list_key, current_map_key)
        end

      # 최상위 key: value 형식
      true ->
        case String.split(trimmed, ":", parts: 2) do
          [key, ""] ->
            key = String.trim(key)
            # 중첩 맵 또는 리스트 시작 확인
            {next_type, _} = peek_next_line(rest)

            case next_type do
              :list -> parse_yaml_lines(rest, acc, key, nil)
              :nested -> parse_yaml_lines(rest, Map.put(acc, key, %{}), nil, key)
              _ -> parse_yaml_lines(rest, acc, key, nil)
            end

          [key, value] ->
            key = String.trim(key)
            value = String.trim(value)
            acc = Map.put(acc, key, parse_value(value))
            parse_yaml_lines(rest, acc, nil, nil)

          _ ->
            parse_yaml_lines(rest, acc, current_list_key, current_map_key)
        end
    end
  end

  defp get_indent(line) do
    original_length = String.length(line)
    trimmed_length = String.length(String.trim_leading(line))
    original_length - trimmed_length
  end

  defp peek_next_line([]), do: {:none, 0}

  defp peek_next_line([line | _]) do
    trimmed = String.trim(line)
    indent = get_indent(line)

    cond do
      trimmed == "" -> {:none, 0}
      String.starts_with?(trimmed, "- ") -> {:list, indent}
      indent > 0 -> {:nested, indent}
      true -> {:none, 0}
    end
  end

  defp parse_value(value) do
    cond do
      value =~ ~r/^\d+\.\d+$/ -> String.to_float(value)
      value =~ ~r/^\d+$/ -> String.to_integer(value)
      value in ["true", "false"] -> value == "true"
      true -> value
    end
  end

  # 이름 검증 (Agent Skills 명세)
  # - 1-64자
  # - 소문자, 숫자, 하이픈만 허용
  # - 하이픈으로 시작/끝 불가
  # - 연속 하이픈 불가
  # - 디렉토리명과 일치 필수
  defp validate_name(nil, _dir_name), do: {:error, "name is required in frontmatter"}

  defp validate_name(name, dir_name) when is_binary(name) do
    cond do
      name != dir_name ->
        {:error, "name '#{name}' must match directory name '#{dir_name}'"}

      String.length(name) == 0 ->
        {:error, "name cannot be empty"}

      String.length(name) > 64 ->
        {:error, "name exceeds 64 characters (got #{String.length(name)})"}

      String.starts_with?(name, "-") ->
        {:error, "name cannot start with hyphen"}

      String.ends_with?(name, "-") ->
        {:error, "name cannot end with hyphen"}

      String.contains?(name, "--") ->
        {:error, "name cannot contain consecutive hyphens"}

      not Regex.match?(~r/^[a-z0-9-]+$/, name) ->
        {:error, "name must contain only lowercase letters, numbers, and hyphens"}

      true ->
        :ok
    end
  end

  defp validate_name(_, _), do: {:error, "name must be a string"}

  # 설명 검증 (1-1024자)
  defp validate_description(nil), do: {:error, "description is required in frontmatter"}

  defp validate_description(desc) when is_binary(desc) do
    len = String.length(desc)

    cond do
      len == 0 -> {:error, "description cannot be empty"}
      len > 1024 -> {:error, "description exceeds 1024 characters (got #{len})"}
      true -> :ok
    end
  end

  defp validate_description(_), do: {:error, "description must be a string"}

  # 호환성 검증 (선택, 최대 500자)
  defp validate_compatibility(nil), do: :ok

  defp validate_compatibility(compat) when is_binary(compat) do
    if String.length(compat) > 500 do
      {:error, "compatibility exceeds 500 characters"}
    else
      :ok
    end
  end

  defp validate_compatibility(_), do: {:error, "compatibility must be a string"}

  # space-delimited string을 리스트로 파싱 (Agent Skills 명세: allowed-tools)
  defp parse_allowed_tools(nil), do: nil

  defp parse_allowed_tools(tools) when is_binary(tools) do
    tools
    |> String.split(~r/\s+/, trim: true)
  end

  defp parse_allowed_tools(tools) when is_list(tools), do: tools
  defp parse_allowed_tools(_), do: nil

  defp parse_status("active"), do: :active
  defp parse_status("inactive"), do: :inactive
  defp parse_status(_), do: :active

  defp extract_workflow(body) do
    case Regex.run(~r/## Workflow\n\n(.*?)(?=\n## |$)/s, body) do
      [_, workflow] -> String.trim(workflow)
      _ -> ""
    end
  end

  defp extract_examples(body) do
    case Regex.run(~r/## Examples\n\n(.*?)(?=\n## |$)/s, body) do
      [_, examples] -> String.trim(examples)
      _ -> ""
    end
  end

  defp format_skill_for_prompt(skill) do
    tools_text =
      if Enum.empty?(skill.allowed_tools),
        do: "없음",
        else: Enum.join(skill.allowed_tools, ", ")

    optional_fields =
      [
        if(skill.license, do: "**라이선스**: #{skill.license}"),
        if(skill.compatibility, do: "**호환성**: #{skill.compatibility}")
      ]
      |> Enum.filter(& &1)
      |> Enum.join("\n\n")

    optional_section = if optional_fields != "", do: "\n\n#{optional_fields}", else: ""

    """
    ### #{skill.display_name}

    **설명**: #{skill.description}

    **사용 도구**: #{tools_text}#{optional_section}

    **워크플로우**:
    #{skill.workflow}

    **사용 예시**:
    #{skill.examples}
    """
  end
end
