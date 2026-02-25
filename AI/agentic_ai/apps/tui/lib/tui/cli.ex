defmodule TUI.CLI do
  @moduledoc """
  ANSI 기반 CLI 인터페이스.

  터미널에서 AI 비서와 대화할 수 있는 인터랙티브 CLI를 제공합니다.

  ## 명령어

    - `/new` - 새 대화 시작
    - `/list` - 대화 목록 보기
    - `/select <number>` - 대화 선택
    - `/delete <number>` - 대화 삭제
    - `/profile` - 사용자 프로필 보기
    - `/clear` - 화면 지우기
    - `/help` - 도움말
    - `/quit` 또는 `/exit` - 종료
  """

  require Logger

  alias TUI.Chat.Handler
  alias TUI.CLI.{Printer, State}

  @doc """
  CLI를 시작합니다.
  """
  def start(opts \\ []) do
    Printer.clear_screen()
    Printer.print_header()

    # 초기 상태 설정
    state = State.new()

    # 대화 목록 로드
    state =
      case Handler.list_conversations() do
        {:ok, conversations} ->
          %{state | conversations: conversations}

        {:error, _} ->
          state
      end

    # 사용자 프로필 로드
    state =
      case Handler.get_user_profile() do
        {:ok, profile} ->
          %{state | user_profile: profile}

        {:error, _} ->
          state
      end

    # 옵션에서 대화 ID가 있으면 선택
    state =
      case Keyword.get(opts, :conversation_id) do
        nil ->
          # 첫 대화가 있으면 자동 선택
          if length(state.conversations) > 0 do
            first = hd(state.conversations)
            select_conversation(state, first.id)
          else
            Printer.print_welcome()
            state
          end

        conv_id ->
          select_conversation(state, conv_id)
      end

    # 메인 루프 시작
    loop(state)
  end

  defp loop(state) do
    prompt = build_prompt(state)
    input = IO.gets(prompt) |> String.trim()

    case process_input(state, input) do
      {:continue, new_state} ->
        loop(new_state)

      :quit ->
        Printer.print_goodbye()
        :ok
    end
  end

  defp build_prompt(state) do
    user_name =
      if state.user_profile do
        Map.get(state.user_profile, "user_name") ||
          Map.get(state.user_profile, :user_name, "You")
      else
        "You"
      end

    conv_indicator =
      if state.current_conversation do
        "[#{truncate(state.current_conversation.title, 20)}]"
      else
        "[No conversation]"
      end

    "\n#{Printer.cyan(conv_indicator)} #{Printer.green(user_name)} > "
  end

  defp process_input(state, input) do
    cond do
      # 빈 입력
      input == "" ->
        {:continue, state}

      # 명령어
      String.starts_with?(input, "/") ->
        handle_command(state, input)

      # 일반 메시지
      true ->
        handle_message(state, input)
    end
  end

  defp handle_command(state, input) do
    [command | args] = String.split(input, " ", parts: 2)
    args = if args == [], do: "", else: hd(args)

    case command do
      "/new" ->
        create_new_conversation(state)

      "/list" ->
        list_conversations(state)

      "/select" ->
        select_conversation_by_index(state, args)

      "/delete" ->
        delete_conversation_by_index(state, args)

      "/profile" ->
        show_profile(state)

      "/clear" ->
        Printer.clear_screen()
        Printer.print_header()
        {:continue, state}

      "/help" ->
        print_help()
        {:continue, state}

      "/quit" ->
        :quit

      "/exit" ->
        :quit

      _ ->
        Printer.print_error("알 수 없는 명령어: #{command}")
        Printer.print_info("도움말을 보려면 /help 를 입력하세요.")
        {:continue, state}
    end
  end

  defp handle_message(state, message) do
    if state.current_conversation_id == nil do
      Printer.print_error("먼저 대화를 시작하세요. /new 또는 /list 명령어를 사용하세요.")
      {:continue, state}
    else
      # 메시지 전송
      Handler.send_message(state.current_conversation_id, message)

      # 스트리밍 응답 수신
      new_state = receive_streaming_response(state)

      {:continue, new_state}
    end
  end

  defp receive_streaming_response(state) do
    agent_name =
      if state.user_profile do
        Map.get(state.user_profile, "agent_name") ||
          Map.get(state.user_profile, :agent_name, "AI")
      else
        "AI"
      end

    IO.write("\n#{Printer.green(agent_name)} > ")

    receive_loop(state, "")
  end

  defp receive_loop(state, accumulated) do
    # Handler에서 대기 중인 메시지 확인
    messages = Handler.get_pending_messages()

    {new_accumulated, done} =
      Enum.reduce(messages, {accumulated, false}, fn msg, {acc, is_done} ->
        case msg do
          {:stream_chunk, text} ->
            IO.write(text)
            {acc <> text, is_done}

          {:stream_tool_start, tool_names} ->
            IO.write("\n#{Printer.yellow("[도구 실행: #{Enum.join(tool_names, ", ")}]")} ")
            {acc, is_done}

          {:stream_tool_end} ->
            IO.write("#{Printer.yellow("[완료]")}\n")
            {acc, is_done}

          {:stream_postprocess} ->
            IO.write("\n#{Printer.magenta("[후처리 중...]")}")
            {acc, is_done}

          {:stream_finish} ->
            {acc, is_done}

          {:stream_complete, response} ->
            # 스트리밍 완료
            IO.write("\n")
            {response, true}

          {:stream_error, reason} ->
            IO.write("\n#{Printer.red("[오류: #{inspect(reason)}]")}\n")
            {acc, true}

          _ ->
            {acc, is_done}
        end
      end)

    if done do
      state
    else
      # 100ms 대기 후 다시 확인
      Process.sleep(100)
      receive_loop(state, new_accumulated)
    end
  end

  defp create_new_conversation(state) do
    case Handler.create_conversation() do
      {:ok, _} ->
        # pending_messages에서 conversation_created 메시지를 가져옴
        Process.sleep(100)
        messages = Handler.get_pending_messages()

        new_state =
          Enum.reduce(messages, state, fn msg, acc ->
            case msg do
              {:conversation_created, conversation} ->
                Printer.print_success("새 대화가 생성되었습니다: #{conversation.title}")

                %{acc |
                  conversations: [conversation | acc.conversations],
                  current_conversation_id: conversation.id,
                  current_conversation: conversation,
                  messages: []
                }

              _ ->
                acc
            end
          end)

        {:continue, new_state}

      {:error, reason} ->
        Printer.print_error("대화 생성 실패: #{inspect(reason)}")
        {:continue, state}
    end
  end

  defp list_conversations(state) do
    # 최신 목록 가져오기
    state =
      case Handler.list_conversations() do
        {:ok, conversations} ->
          %{state | conversations: conversations}

        {:error, _} ->
          state
      end

    if Enum.empty?(state.conversations) do
      Printer.print_info("대화가 없습니다. /new 명령어로 새 대화를 시작하세요.")
    else
      IO.puts("\n#{Printer.bold("=== 대화 목록 ===")}")

      state.conversations
      |> Enum.with_index(1)
      |> Enum.each(fn {conv, idx} ->
        current_marker = if conv.id == state.current_conversation_id, do: "*", else: " "
        IO.puts("#{current_marker} #{idx}. #{conv.title}")
      end)

      IO.puts("")
      Printer.print_info("대화를 선택하려면 /select <번호> 를 입력하세요.")
    end

    {:continue, state}
  end

  defp select_conversation_by_index(state, index_str) do
    case Integer.parse(index_str) do
      {index, _} when index > 0 and index <= length(state.conversations) ->
        conv = Enum.at(state.conversations, index - 1)
        new_state = select_conversation(state, conv.id)
        {:continue, new_state}

      _ ->
        Printer.print_error("유효한 번호를 입력하세요.")
        {:continue, state}
    end
  end

  defp select_conversation(state, conversation_id) do
    case Handler.select_conversation(conversation_id) do
      {:ok, conversation} ->
        # pending_messages에서 메시지 로드 결과를 가져옴
        Process.sleep(100)
        messages = Handler.get_pending_messages()

        loaded_messages =
          Enum.find_value(messages, [], fn
            {:messages_loaded, msgs} -> msgs
            _ -> false
          end)

        Printer.print_success("대화 선택됨: #{conversation.title}")

        # 최근 메시지 표시
        if length(loaded_messages) > 0 do
          IO.puts("\n#{Printer.bold("=== 최근 메시지 ===")}")

          loaded_messages
          |> Enum.take(-5)
          |> Enum.each(fn msg ->
            role_label =
              case msg.role do
                :user -> Printer.blue("[You]")
                "user" -> Printer.blue("[You]")
                :assistant -> Printer.green("[AI]")
                "assistant" -> Printer.green("[AI]")
                _ -> "[#{msg.role}]"
              end

            content = truncate(msg.content, 100)
            IO.puts("#{role_label} #{content}")
          end)

          IO.puts("#{Printer.cyan("...")}")
        end

        %{state |
          current_conversation_id: conversation_id,
          current_conversation: conversation,
          messages: loaded_messages
        }

      {:error, reason} ->
        Printer.print_error("대화 선택 실패: #{inspect(reason)}")
        state
    end
  end

  defp delete_conversation_by_index(state, index_str) do
    case Integer.parse(index_str) do
      {index, _} when index > 0 and index <= length(state.conversations) ->
        conv = Enum.at(state.conversations, index - 1)

        case Handler.delete_conversation(conv.id) do
          :ok ->
            Printer.print_success("대화가 삭제되었습니다: #{conv.title}")

            new_conversations = Enum.reject(state.conversations, &(&1.id == conv.id))

            new_state =
              if state.current_conversation_id == conv.id do
                # 현재 대화가 삭제된 경우
                if length(new_conversations) > 0 do
                  first = hd(new_conversations)
                  select_conversation(%{state | conversations: new_conversations}, first.id)
                else
                  %{state |
                    conversations: [],
                    current_conversation_id: nil,
                    current_conversation: nil,
                    messages: []
                  }
                end
              else
                %{state | conversations: new_conversations}
              end

            {:continue, new_state}

          {:error, reason} ->
            Printer.print_error("대화 삭제 실패: #{inspect(reason)}")
            {:continue, state}
        end

      _ ->
        Printer.print_error("유효한 번호를 입력하세요.")
        {:continue, state}
    end
  end

  defp show_profile(state) do
    case state.user_profile do
      nil ->
        Printer.print_info("프로필이 설정되지 않았습니다.")

      profile ->
        IO.puts("\n#{Printer.bold("=== 사용자 프로필 ===")}")

        user_name = Map.get(profile, "user_name") || Map.get(profile, :user_name, "미설정")
        agent_name = Map.get(profile, "agent_name") || Map.get(profile, :agent_name, "미설정")
        city = Map.get(profile, "city") || Map.get(profile, :city, "미설정")

        IO.puts("  이름: #{user_name}")
        IO.puts("  AI 이름: #{agent_name}")
        IO.puts("  도시: #{city}")
    end

    {:continue, state}
  end

  defp print_help do
    IO.puts("""

    #{Printer.bold("=== 도움말 ===")}

    #{Printer.cyan("대화 관리:")}
      /new              새 대화 시작
      /list             대화 목록 보기
      /select <번호>    대화 선택
      /delete <번호>    대화 삭제

    #{Printer.cyan("기타:")}
      /profile          사용자 프로필 보기
      /clear            화면 지우기
      /help             이 도움말 보기
      /quit, /exit      종료

    #{Printer.cyan("일반 사용:")}
      메시지를 입력하고 Enter를 누르면 AI가 응답합니다.
      계산, 웹 검색, 날씨 등 다양한 도구를 사용할 수 있습니다.

    #{Printer.cyan("예시:")}
      > 안녕하세요!
      > 2 + 2는 뭐야?
      > 오늘 날씨 어때?
    """)
  end

  defp truncate(text, max_len) when is_binary(text) do
    text = String.replace(text, ~r/\n+/, " ")

    if String.length(text) > max_len do
      String.slice(text, 0, max_len - 3) <> "..."
    else
      text
    end
  end

  defp truncate(_, _), do: ""
end
