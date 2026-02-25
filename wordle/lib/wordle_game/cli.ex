defmodule WordleGame.CLI do
  @moduledoc """
  Wordle 게임 CLI 인터페이스
  """

  alias WordleGame.{Game, Words}

  @doc """
  게임을 시작합니다.
  """
  def main(_args \\ []) do
    IO.puts("""

    ╔═══════════════════════════════════════╗
    ║         🎯 WORDLE GAME 🎯             ║
    ║     5글자 영어 단어 맞추기 게임       ║
    ╠═══════════════════════════════════════╣
    ║  🟩 = 정확한 위치                     ║
    ║  🟨 = 단어에 포함 (다른 위치)         ║
    ║  ⬜ = 단어에 없음                     ║
    ║                                       ║
    ║  6번의 기회 안에 단어를 맞추세요!     ║
    ╚═══════════════════════════════════════╝
    """)

    game = WordleGame.new_game()
    play(game)
  end

  defp play(game) do
    remaining = Game.remaining_guesses(game)
    IO.puts("\n남은 기회: #{remaining}번")

    # 이전 추측 결과 표시
    display_guesses(game.guesses)

    case IO.gets("단어 입력: ") do
      :eof ->
        IO.puts("\n게임 종료!")

      input ->
        word = input |> String.trim() |> String.downcase()

        cond do
          word == "quit" or word == "exit" ->
            IO.puts("\n게임을 종료합니다. 정답은 '#{game.target}' 였습니다!")

          word == "hint" ->
            give_hint(game)
            play(game)

          true ->
            handle_guess(game, word)
        end
    end
  end

  defp handle_guess(game, word) do
    case Game.guess(game, word) do
      {:ok, result, new_game} ->
        display_result(word, result)

        cond do
          Game.won?(new_game) ->
            attempts = length(new_game.guesses)
            IO.puts("""

            🎉 축하합니다! 정답입니다! 🎉
            #{attempts}번 만에 맞추셨습니다!
            """)
            play_again?()

          Game.game_over?(new_game) ->
            IO.puts("""

            😢 게임 오버!
            정답은 '#{new_game.target}' 였습니다.
            """)
            play_again?()

          true ->
            play(new_game)
        end

      {:error, :invalid_word, game} ->
        IO.puts("⚠️  5글자 영어 단어만 입력하세요!")
        play(game)

      {:error, :already_guessed, game} ->
        IO.puts("⚠️  이미 시도한 단어입니다!")
        play(game)

      {:error, :game_over, game} ->
        IO.puts("게임이 이미 종료되었습니다.")
        play_again?()
    end
  end

  defp display_guesses([]), do: :ok

  defp display_guesses(guesses) do
    IO.puts("\n┌─────────────┐")
    for {word, result} <- guesses do
      display_result(word, result)
    end
    IO.puts("└─────────────┘")
  end

  defp display_result(word, result) do
    chars = String.graphemes(String.upcase(word))

    emoji_line =
      result
      |> Enum.map(fn
        :correct -> "🟩"
        :present -> "🟨"
        :absent -> "⬜"
      end)
      |> Enum.join("")

    letter_line =
      chars
      |> Enum.map(&" #{&1} ")
      |> Enum.join("")

    IO.puts("│ #{emoji_line} │")
    IO.puts("│#{letter_line}│")
  end

  defp give_hint(game) do
    target_chars = String.graphemes(game.target)
    guessed_chars =
      game.guesses
      |> Enum.flat_map(fn {word, _} -> String.graphemes(word) end)
      |> Enum.uniq()

    unguessed =
      target_chars
      |> Enum.reject(&(&1 in guessed_chars))

    case unguessed do
      [] ->
        IO.puts("💡 힌트: 이미 모든 글자를 시도했습니다!")
      chars ->
        hint_char = Enum.random(chars)
        IO.puts("💡 힌트: 단어에 '#{String.upcase(hint_char)}' 글자가 포함되어 있습니다!")
    end
  end

  defp play_again? do
    case IO.gets("\n다시 하시겠습니까? (y/n): ") do
      :eof ->
        IO.puts("안녕히 가세요! 👋")

      input ->
        case String.trim(String.downcase(input)) do
          "y" ->
            game = WordleGame.new_game()
            play(game)
          "yes" ->
            game = WordleGame.new_game()
            play(game)
          _ ->
            IO.puts("안녕히 가세요! 👋")
        end
    end
  end
end
