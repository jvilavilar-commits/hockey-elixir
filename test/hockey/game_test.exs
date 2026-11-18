defmodule Hockey.GameTest do
  use ExUnit.Case, async: true

  alias Hockey.{Game, Physics}

  defp full_game do
    Enum.reduce(1..4, Game.new(), &Game.add_player(&2, &1))
  end

  test "la partida comienza automáticamente con cuatro jugadores" do
    game = full_game()
    assert game.phase == :playing
    assert map_size(game.players) == 4
    assert game.score == %{blue: 0, red: 0}
    assert game.time_left == 180.0
  end

  test "el movimiento es una transformación pura y respeta los límites" do
    game = full_game()
    original = game.players[1]

    moved =
      game
      |> Game.put_input(1, %{up: false, down: false, left: false, right: true, kick: false})
      |> Game.tick(0.1)

    assert moved.players[1].pos != original.pos
    assert elem(moved.players[1].pos, 0) > elem(original.pos, 0)
    assert game.players[1] == original
  end

  test "detecta el gol, suma el marcador y recoloca el disco" do
    game = %{full_game() | puck: %{pos: {1016.0, 300.0}, vel: {80.0, 0.0}}}
    scored = Game.tick(game, 0.016)

    assert scored.phase == :goal_pause
    assert scored.score == %{blue: 1, red: 0}
    assert scored.last_goal == :blue
    assert scored.puck.pos == {500.0, 300.0}
    assert scored.players[1].pos == Physics.spawn_position(1)
  end

  test "finaliza a los tres minutos y permite empate" do
    finished = Game.tick(%{full_game() | time_left: 0.01}, 0.02)
    assert finished.phase == :finished
    assert finished.time_left == 0.0
    assert finished.winner == :draw
  end

  test "pausa ante desconexión y reanuda sin descontar tiempo" do
    game = full_game()
    paused = Game.set_connected(game, 3, false)
    after_tick = Game.tick(paused, 2.0)

    assert paused.phase == :paused
    assert after_tick.time_left == 180.0
    assert Game.set_connected(after_tick, 3, true).phase == :playing
  end

  test "una revancha reinicia marcador, reloj y posiciones" do
    finished = %{
      full_game()
      | phase: :finished,
        score: %{blue: 4, red: 2},
        time_left: 0.0,
        winner: :blue
    }

    rematch = Game.rematch(finished)

    assert rematch.phase == :playing
    assert rematch.score == %{blue: 0, red: 0}
    assert rematch.time_left == 180.0
    assert rematch.winner == nil
  end
end
