defmodule TUI.CLI.Printer do
  @moduledoc """
  ANSI 색상 및 포맷팅 유틸리티.
  """

  # ANSI 색상 코드
  @reset "\e[0m"
  @bold "\e[1m"
  @red "\e[31m"
  @green "\e[32m"
  @yellow "\e[33m"
  @blue "\e[34m"
  @magenta "\e[35m"
  @cyan "\e[36m"
  @white "\e[37m"

  @doc "화면 지우기"
  def clear_screen do
    IO.write("\e[2J\e[H")
  end

  @doc "헤더 출력"
  def print_header do
    IO.puts("""
    #{cyan("╔════════════════════════════════════════════════════════════╗")}
    #{cyan("║")}#{bold("              Agentic AI - Terminal Interface              ")}#{cyan("║")}
    #{cyan("║")}          Azure OpenAI gpt-5-mini powered               #{cyan("║")}
    #{cyan("╚════════════════════════════════════════════════════════════╝")}
    """)
  end

  @doc "환영 메시지 출력"
  def print_welcome do
    IO.puts("""
    #{green("환영합니다!")} AI 비서와 대화를 시작하세요.

    #{cyan("시작하기:")}
      • #{bold("/new")} - 새 대화 시작
      • #{bold("/list")} - 기존 대화 목록 보기
      • #{bold("/help")} - 도움말 보기

    """)
  end

  @doc "종료 메시지 출력"
  def print_goodbye do
    IO.puts("\n#{green("감사합니다! 다음에 또 만나요. 👋")}\n")
  end

  @doc "성공 메시지 출력"
  def print_success(message) do
    IO.puts("#{green("✓")} #{message}")
  end

  @doc "오류 메시지 출력"
  def print_error(message) do
    IO.puts("#{red("✗")} #{message}")
  end

  @doc "정보 메시지 출력"
  def print_info(message) do
    IO.puts("#{cyan("ℹ")} #{message}")
  end

  @doc "경고 메시지 출력"
  def print_warning(message) do
    IO.puts("#{yellow("⚠")} #{message}")
  end

  # 색상 함수들
  def bold(text), do: "#{@bold}#{text}#{@reset}"
  def red(text), do: "#{@red}#{text}#{@reset}"
  def green(text), do: "#{@green}#{text}#{@reset}"
  def yellow(text), do: "#{@yellow}#{text}#{@reset}"
  def blue(text), do: "#{@blue}#{text}#{@reset}"
  def magenta(text), do: "#{@magenta}#{text}#{@reset}"
  def cyan(text), do: "#{@cyan}#{text}#{@reset}"
  def white(text), do: "#{@white}#{text}#{@reset}"
end
