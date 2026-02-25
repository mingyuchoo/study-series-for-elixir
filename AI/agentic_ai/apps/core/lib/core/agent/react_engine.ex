defmodule Core.Agent.ReactEngine do
  @moduledoc """
  ReAct (Reasoning + Acting) 패턴 엔진.

  에이전트가 도구를 사용하며 작업을 수행하는 핵심 로직을 제공합니다.
  순수 함수 기반으로 설계되어 다양한 에이전트 타입에서 재사용 가능합니다.
  """

  require Logger
  alias Core.LLM.AzureOpenAI
  alias Core.Agent.ToolRegistry

  @type message :: %{
          role: String.t(),
          content: String.t(),
          tool_calls: list() | nil,
          tool_call_id: String.t() | nil
        }

  @type tool :: %{
          name: String.t(),
          description: String.t(),
          parameters: map()
        }

  @type result ::
          {:ok, String.t(), list(message())}
          | {:error, atom() | String.t()}

  @doc """
  ReAct 루프를 실행합니다.

  ## Parameters

    - `messages`: 대화 메시지 목록
    - `tools`: 사용 가능한 도구 목록
    - `opts`: 옵션
      - `:max_iterations` - 최대 반복 횟수 (기본값: 10)
      - `:system_prompt` - 시스템 프롬프트 (기본값: nil)

  ## Returns

    - `{:ok, response, messages}` - 성공 시 최종 응답과 업데이트된 메시지 목록
    - `{:error, reason}` - 실패 시 오류 원인

  ## Examples

      iex> ReactEngine.run([], tools, system_prompt: "You are a helpful assistant")
      {:ok, "안녕하세요!", [%{role: "assistant", content: "안녕하세요!", ...}]}
  """
  @spec run(list(message()), list(tool()), keyword()) :: result()
  def run(messages, tools, opts \\ []) do
    max_iterations = Keyword.get(opts, :max_iterations, 10)
    system_prompt = Keyword.get(opts, :system_prompt)

    messages_with_system =
      if system_prompt do
        [%{role: "system", content: system_prompt} | messages]
      else
        messages
      end

    agent_loop(messages_with_system, tools, 0, max_iterations)
  end

  @doc """
  스트리밍 모드로 ReAct 루프를 실행합니다.

  ## Parameters

    - `messages`: 대화 메시지 목록
    - `tools`: 사용 가능한 도구 목록
    - `stream_callback`: 각 청크에 대해 호출되는 콜백 함수
    - `opts`: 옵션
      - `:max_iterations` - 최대 반복 횟수 (기본값: 10)
      - `:system_prompt` - 시스템 프롬프트 (기본값: nil)

  ## Returns

    - `{:ok, response, messages}` - 성공 시 최종 응답과 업데이트된 메시지 목록
    - `{:error, reason}` - 실패 시 오류 원인
  """
  @spec run_stream(list(message()), list(tool()), (String.t() -> any()), keyword()) :: result()
  def run_stream(messages, tools, stream_callback, opts \\ []) do
    max_iterations = Keyword.get(opts, :max_iterations, 10)
    system_prompt = Keyword.get(opts, :system_prompt)

    messages_with_system =
      if system_prompt do
        [%{role: "system", content: system_prompt} | messages]
      else
        messages
      end

    agent_loop_stream(messages_with_system, tools, stream_callback, 0, max_iterations)
  end

  # 비공개 함수들

  defp agent_loop(_messages, _tools, iteration, max_iterations)
       when iteration >= max_iterations do
    Logger.warning("Max iterations (#{max_iterations}) reached")
    {:error, :max_iterations_reached}
  end

  defp agent_loop(messages, tools, iteration, max_iterations) do
    formatted_messages = format_messages_for_api(messages)
    formatted_tools = format_tools_for_api(tools)

    case AzureOpenAI.chat_completion(formatted_messages, tools: formatted_tools) do
      {:ok, %{tool_calls: nil, content: content}} ->
        # 도구 호출 없음 - 최종 응답 반환
        assistant_message = %{
          role: "assistant",
          content: content,
          tool_calls: nil,
          tool_call_id: nil
        }

        {:ok, content, messages ++ [assistant_message]}

      {:ok, %{tool_calls: tool_calls, content: content}} when is_list(tool_calls) ->
        # 도구 호출 존재 - 도구 실행 후 루프 계속
        assistant_message = %{
          role: "assistant",
          content: content || "",
          tool_calls: tool_calls,
          tool_call_id: nil
        }

        messages_after_assistant = messages ++ [assistant_message]
        messages_after_tools = execute_tool_calls(messages_after_assistant, tool_calls)

        agent_loop(messages_after_tools, tools, iteration + 1, max_iterations)

      {:error, reason} ->
        Logger.error("LLM API call failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # 스트리밍 버전의 agent_loop
  defp agent_loop_stream(_messages, _tools, _stream_callback, iteration, max_iterations)
       when iteration >= max_iterations do
    Logger.warning("Max iterations (#{max_iterations}) reached in streaming mode")
    {:error, :max_iterations_reached}
  end

  defp agent_loop_stream(messages, tools, stream_callback, iteration, max_iterations) do
    formatted_messages = format_messages_for_api(messages)
    formatted_tools = format_tools_for_api(tools)

    # 스트리밍 응답 수집을 위한 상태
    state = %{
      content: "",
      tool_calls: [],
      current_tool_call: nil,
      finish_reason: nil
    }

    # 스트리밍 콜백 래퍼 - 청크를 수집하면서 실시간으로 콜백 호출
    {final_state, _} =
      stream_with_callback(formatted_messages, formatted_tools, stream_callback, state)

    case final_state do
      %{tool_calls: [], content: content} when content != "" ->
        # 도구 호출 없음 - 최종 응답 반환
        assistant_message = %{
          role: "assistant",
          content: content,
          tool_calls: nil,
          tool_call_id: nil
        }

        {:ok, content, messages ++ [assistant_message]}

      %{tool_calls: tool_calls, content: content} when is_list(tool_calls) and tool_calls != [] ->
        # 도구 호출 존재 - 도구 실행 후 루프 계속
        # 도구 실행 중임을 알림
        stream_callback.({:tool_execution, tool_calls})

        assistant_message = %{
          role: "assistant",
          content: content || "",
          tool_calls: tool_calls,
          tool_call_id: nil
        }

        messages_after_assistant = messages ++ [assistant_message]
        messages_after_tools = execute_tool_calls(messages_after_assistant, tool_calls)

        # 도구 실행 완료 알림
        stream_callback.({:tool_completed, tool_calls})

        agent_loop_stream(
          messages_after_tools,
          tools,
          stream_callback,
          iteration + 1,
          max_iterations
        )

      %{error: reason} ->
        {:error, reason}

      _ ->
        # 빈 응답 처리
        {:ok, "", messages}
    end
  end

  defp stream_with_callback(messages, tools, stream_callback, initial_state) do
    # 상태를 프로세스 딕셔너리에 저장 (스트리밍 콜백에서 접근용)
    Process.put(:stream_state, initial_state)
    Process.put(:stream_callback, stream_callback)

    result =
      AzureOpenAI.stream_chat_completion(
        messages,
        [tools: tools],
        fn data ->
          state = Process.get(:stream_state)
          callback = Process.get(:stream_callback)
          new_state = process_stream_data(data, state, callback)
          Process.put(:stream_state, new_state)
        end
      )

    final_state = Process.get(:stream_state)
    Process.delete(:stream_state)
    Process.delete(:stream_callback)

    {final_state, result}
  end

  defp process_stream_data(%{"choices" => [choice | _]}, state, callback) do
    delta = choice["delta"] || %{}
    finish_reason = choice["finish_reason"]

    # 텍스트 콘텐츠 처리
    state =
      case delta["content"] do
        nil ->
          state

        "" ->
          state

        content ->
          # 실시간으로 텍스트 청크 전송
          callback.({:chunk, content})
          %{state | content: state.content <> content}
      end

    # 도구 호출 처리
    state =
      case delta["tool_calls"] do
        nil ->
          state

        tool_calls when is_list(tool_calls) ->
          Enum.reduce(tool_calls, state, fn tc, acc ->
            process_tool_call_delta(tc, acc)
          end)
      end

    # 완료 처리
    state =
      if finish_reason do
        callback.({:finish, finish_reason})
        %{state | finish_reason: finish_reason}
      else
        state
      end

    state
  end

  defp process_stream_data(_data, state, _callback), do: state

  defp process_tool_call_delta(%{"index" => index} = tc, state) do
    existing = Enum.at(state.tool_calls, index)

    updated_tc =
      case existing do
        nil ->
          # 새로운 도구 호출 시작
          %{
            "id" => tc["id"] || "",
            "type" => tc["type"] || "function",
            "function" => %{
              "name" => get_in(tc, ["function", "name"]) || "",
              "arguments" => get_in(tc, ["function", "arguments"]) || ""
            }
          }

        existing_tc ->
          # 기존 도구 호출 업데이트
          func = existing_tc["function"]
          new_func = tc["function"] || %{}

          %{
            existing_tc
            | "id" => tc["id"] || existing_tc["id"],
              "function" => %{
                "name" => (new_func["name"] || "") <> (func["name"] || ""),
                "arguments" => (func["arguments"] || "") <> (new_func["arguments"] || "")
              }
          }
      end

    # 리스트 업데이트
    tool_calls =
      if index >= length(state.tool_calls) do
        state.tool_calls ++ [updated_tc]
      else
        List.replace_at(state.tool_calls, index, updated_tc)
      end

    %{state | tool_calls: tool_calls}
  end

  defp process_tool_call_delta(_tc, state), do: state

  defp execute_tool_calls(messages, tool_calls) do
    tool_messages =
      Enum.map(tool_calls, fn tool_call ->
        function_name = tool_call["function"]["name"]
        arguments = Jason.decode!(tool_call["function"]["arguments"])

        Logger.info("Executing tool: #{function_name} with args: #{inspect(arguments)}")

        result =
          case ToolRegistry.execute(function_name, arguments) do
            {:ok, result} ->
              Jason.encode!(result)

            {:error, reason} ->
              Logger.warning("Tool execution failed: #{inspect(reason)}")
              Jason.encode!(%{error: inspect(reason)})
          end

        %{
          role: "tool",
          content: result,
          tool_calls: nil,
          tool_call_id: tool_call["id"]
        }
      end)

    messages ++ tool_messages
  end

  defp format_messages_for_api(messages) do
    Enum.map(messages, fn msg ->
      base = %{role: msg.role, content: msg.content}

      base
      |> maybe_add(:tool_calls, msg[:tool_calls])
      |> maybe_add(:tool_call_id, msg[:tool_call_id])
    end)
  end

  defp format_tools_for_api(tools) do
    Enum.map(tools, fn tool ->
      %{
        type: "function",
        function: %{
          name: tool.name,
          description: tool.description,
          parameters: tool.parameters
        }
      }
    end)
  end

  defp maybe_add(map, _key, nil), do: map
  defp maybe_add(map, _key, []), do: map
  defp maybe_add(map, key, value), do: Map.put(map, key, value)
end
