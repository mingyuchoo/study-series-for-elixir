defmodule WordleGame.Game do
  @moduledoc """
  Wordle 게임 상태 관리
  """

  alias WordleGame.Words

  defstruct [
    :target,
    :guesses,
    :max_guesses,
    :status
  ]

  @max_guesses 6

  @doc """
  새 게임을 생성합니다.
  """
  def new(target) do
    %__MODULE__{
      target: String.downcase(target),
      guesses: [],
      max_guesses: @max_guesses,
      status: :playing
    }
  end

  @doc """
  단어를 추측합니다.
  """
  def guess(%__MODULE__{status: status} = game, _word) when status != :playing do
    {:error, :game_over, game}
  end

  def guess(%__MODULE__{} = game, word) do
    word = String.downcase(word)

    cond do
      not Words.valid_word?(word) ->
        {:error, :invalid_word, game}

      word in Enum.map(game.guesses, fn {w, _} -> w end) ->
        {:error, :already_guessed, game}

      true ->
        result = check_word(game.target, word)
        guesses = game.guesses ++ [{word, result}]

        status =
          cond do
            word == game.target -> :won
            length(guesses) >= game.max_guesses -> :lost
            true -> :playing
          end

        game = %{game | guesses: guesses, status: status}
        {:ok, result, game}
    end
  end

  @doc """
  단어를 검사하고 힌트를 반환합니다.
  - :correct - 정확한 위치 (🟩)
  - :present - 다른 위치에 존재 (🟨)
  - :absent - 존재하지 않음 (⬜)
  """
  def check_word(target, guess) do
    target_chars = String.graphemes(target)
    guess_chars = String.graphemes(guess)

    # 1단계: 정확한 위치 찾기
    {results, remaining_target} =
      Enum.zip(target_chars, guess_chars)
      |> Enum.with_index()
      |> Enum.reduce({%{}, target_chars}, fn {{t, g}, i}, {results, remaining} ->
        if t == g do
          {Map.put(results, i, :correct), List.replace_at(remaining, i, nil)}
        else
          {results, remaining}
        end
      end)

    # 2단계: 다른 위치에 존재하는지 확인
    {final_results, _} =
      guess_chars
      |> Enum.with_index()
      |> Enum.reduce({results, remaining_target}, fn {char, i}, {results, remaining} ->
        if Map.has_key?(results, i) do
          {results, remaining}
        else
          case Enum.find_index(remaining, &(&1 == char)) do
            nil ->
              {Map.put(results, i, :absent), remaining}

            idx ->
              {Map.put(results, i, :present), List.replace_at(remaining, idx, nil)}
          end
        end
      end)

    # 결과를 리스트로 변환
    0..4
    |> Enum.map(&Map.get(final_results, &1))
  end

  @doc """
  게임이 끝났는지 확인합니다.
  """
  def game_over?(%__MODULE__{status: status}) do
    status != :playing
  end

  @doc """
  게임에서 이겼는지 확인합니다.
  """
  def won?(%__MODULE__{status: status}) do
    status == :won
  end

  @doc """
  남은 시도 횟수를 반환합니다.
  """
  def remaining_guesses(%__MODULE__{guesses: guesses, max_guesses: max}) do
    max - length(guesses)
  end
end
