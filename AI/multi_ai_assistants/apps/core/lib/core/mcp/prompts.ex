defmodule Core.MCP.Prompts do
  @moduledoc """
  MCP Prompts 엔드포인트 구현.

  SkillRegistry의 스킬들을 MCP Prompts로 노출합니다.
  스킬은 재사용 가능한 워크플로우 템플릿으로, AI 모델과의 상호작용을 구조화합니다.

  ## MCP Prompts 명세

  - `prompts/list`: 사용 가능한 모든 프롬프트 목록 반환
  - `prompts/get`: 특정 프롬프트의 전체 내용 반환

  ## 프롬프트 정의 형식

      %{
        "name" => "research-report",
        "title" => "Research Report Generator",
        "description" => "웹 검색으로 정보를 수집하고 보고서 작성",
        "arguments" => [
          %{
            "name" => "topic",
            "description" => "조사할 주제",
            "required" => true
          }
        ]
      }
  """

  alias Core.Agent.SkillRegistry
  alias Core.MCP.Protocol

  @doc """
  모든 프롬프트(스킬) 목록을 반환합니다 (prompts/list).

  ## Returns

      {:ok, %{"prompts" => [...]}}
  """
  def list do
    prompts =
      try do
        SkillRegistry.get_all_skills()
        |> Enum.filter(fn skill -> skill.status == :active end)
        |> Enum.map(&convert_to_mcp_prompt/1)
      rescue
        _ -> []
      end

    {:ok, %{"prompts" => prompts}}
  end

  @doc """
  특정 프롬프트(스킬)의 전체 내용을 반환합니다 (prompts/get).

  ## Parameters

    - `params` - 프롬프트 조회 파라미터
      - `"name"` - 프롬프트(스킬) 이름 (필수)
      - `"arguments"` - 템플릿 변수 값 (선택)

  ## Returns

      {:ok, %{"description" => "...", "messages" => [...]}}
  """
  def get(%{"name" => name} = params) do
    arguments = Map.get(params, "arguments", %{})

    case SkillRegistry.get_skill(name) do
      nil ->
        {:error, Protocol.invalid_params_error("Prompt not found: #{name}")}

      skill ->
        {:ok, format_prompt_response(skill, arguments)}
    end
  rescue
    _ ->
      {:error, Protocol.invalid_params_error("Prompt not found: #{name}")}
  end

  def get(_params) do
    {:error, Protocol.invalid_params_error("Missing required parameter: name")}
  end

  # 비공개 함수들

  defp convert_to_mcp_prompt(skill) do
    %{
      "name" => skill.name,
      "title" => skill.display_name,
      "description" => skill.description,
      "arguments" => extract_arguments(skill)
    }
  end

  defp extract_arguments(skill) do
    # 스킬의 Input Schema에서 arguments 추출
    base_arguments = [
      %{
        "name" => "task",
        "description" => "수행할 작업에 대한 상세 설명",
        "required" => true
      }
    ]

    # 스킬에 필요한 도구들을 기반으로 추가 arguments 생성
    tool_arguments =
      skill.allowed_tools
      |> Enum.map(fn tool ->
        %{
          "name" => "use_#{tool}",
          "description" => "#{tool} 도구 사용 여부",
          "required" => false
        }
      end)

    base_arguments ++ tool_arguments
  end

  defp format_prompt_response(skill, arguments) do
    task = Map.get(arguments, "task", "")

    # 워크플로우 내용을 시스템 메시지로 구성
    system_content = build_system_prompt(skill)

    # 사용자 요청을 사용자 메시지로 구성
    user_content = build_user_prompt(skill, task)

    %{
      "description" => skill.description,
      "messages" => [
        %{
          "role" => "system",
          "content" => %{
            "type" => "text",
            "text" => system_content
          }
        },
        %{
          "role" => "user",
          "content" => %{
            "type" => "text",
            "text" => user_content
          }
        }
      ]
    }
  end

  defp build_system_prompt(skill) do
    tools_text =
      if Enum.empty?(skill.allowed_tools),
        do: "없음",
        else: Enum.join(skill.allowed_tools, ", ")

    """
    # #{skill.display_name}

    ## 설명
    #{skill.description}

    ## 사용 가능한 도구
    #{tools_text}

    ## 워크플로우
    #{skill.workflow}

    ## 예시
    #{skill.examples}

    ---

    위 워크플로우를 참고하여 사용자의 요청을 처리하세요.
    각 단계를 순서대로 수행하고, 필요한 도구를 적절히 활용하세요.
    """
  end

  defp build_user_prompt(skill, task) do
    if task == "" do
      """
      이 스킬(#{skill.display_name})을 사용하여 작업을 수행해주세요.
      워크플로우를 따라 진행하되, 구체적인 작업 내용을 알려주시면 더 정확하게 도움드릴 수 있습니다.
      """
    else
      """
      다음 작업을 #{skill.display_name} 워크플로우에 따라 수행해주세요:

      #{task}
      """
    end
  end
end
