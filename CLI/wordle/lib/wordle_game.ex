defmodule WordleGame do
  @moduledoc """
  Wordle 스타일 단어 맞추기 게임

  5글자 영어 단어를 6번의 시도 안에 맞추는 게임입니다.
  각 시도마다 힌트가 제공됩니다:
  - 🟩 (초록): 정확한 위치에 정확한 글자
  - 🟨 (노랑): 단어에 포함되지만 다른 위치
  - ⬜ (회색): 단어에 포함되지 않음
  """

  alias WordleGame.{Game, Words}

  @doc """
  새 게임을 시작합니다.
  """
  def new_game do
    target = Words.random_word()
    Game.new(target)
  end

  @doc """
  단어를 추측합니다.
  """
  def guess(game, word) do
    Game.guess(game, word)
  end

  @doc """
  게임이 끝났는지 확인합니다.
  """
  def game_over?(game) do
    Game.game_over?(game)
  end

  @doc """
  게임에서 이겼는지 확인합니다.
  """
  def won?(game) do
    Game.won?(game)
  end
end
