defmodule WordleGameTest do
  use ExUnit.Case
  doctest WordleGame

  alias WordleGame.{Game, Words}

  describe "Words" do
    test "random_word returns a 5-letter word" do
      word = Words.random_word()
      assert String.length(word) == 5
    end

    test "valid_word? accepts 5-letter words" do
      assert Words.valid_word?("hello")
      assert Words.valid_word?("WORLD")
      refute Words.valid_word?("hi")
      refute Words.valid_word?("toolong")
      refute Words.valid_word?("12345")
    end
  end

  describe "Game" do
    test "new game has correct initial state" do
      game = Game.new("hello")
      assert game.target == "hello"
      assert game.guesses == []
      assert game.status == :playing
    end

    test "correct guess wins the game" do
      game = Game.new("hello")
      {:ok, result, game} = Game.guess(game, "hello")

      assert result == [:correct, :correct, :correct, :correct, :correct]
      assert game.status == :won
    end

    test "check_word returns correct hints" do
      # All correct
      assert Game.check_word("hello", "hello") == [:correct, :correct, :correct, :correct, :correct]

      # All absent
      assert Game.check_word("hello", "quirk") == [:absent, :absent, :absent, :absent, :absent]

      # Mixed: 'e' is present but wrong position
      result = Game.check_word("hello", "eagle")
      assert Enum.at(result, 0) == :present  # e is in hello but not at position 0
      assert Enum.at(result, 4) == :absent   # e is already counted

      # 'l' in correct position
      result = Game.check_word("hello", "jello")
      assert Enum.at(result, 1) == :correct  # e
      assert Enum.at(result, 2) == :correct  # l
      assert Enum.at(result, 3) == :correct  # l
      assert Enum.at(result, 4) == :correct  # o
    end

    test "game over after max guesses" do
      game = Game.new("hello")

      game = Enum.reduce(1..6, game, fn _, acc ->
        {:ok, _, new_game} = Game.guess(acc, "world")
        new_game
      end)

      assert game.status == :lost
      assert Game.game_over?(game)
    end

    test "cannot guess after game over" do
      game = Game.new("hello")
      {:ok, _, game} = Game.guess(game, "hello")

      assert {:error, :game_over, _} = Game.guess(game, "world")
    end

    test "invalid word is rejected" do
      game = Game.new("hello")

      assert {:error, :invalid_word, _} = Game.guess(game, "hi")
      assert {:error, :invalid_word, _} = Game.guess(game, "123ab")
    end

    test "duplicate guess is rejected" do
      game = Game.new("hello")
      {:ok, _, game} = Game.guess(game, "world")

      assert {:error, :already_guessed, _} = Game.guess(game, "world")
    end
  end
end
