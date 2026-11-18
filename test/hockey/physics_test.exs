defmodule Hockey.PhysicsTest do
  use ExUnit.Case, async: true

  alias Hockey.{Game, Physics}

  defp game do
    Enum.reduce(1..4, Game.new(), &Game.add_player(&2, &1))
  end

  test "el disco rebota contra el borde fuera de la portería" do
    state = %{game() | puck: %{pos: {35.0, 100.0}, vel: {-250.0, 0.0}}}
    next = Physics.step(state, 0.05)

    assert elem(next.puck.pos, 0) >= 39.0
    assert elem(next.puck.vel, 0) > 0
  end

  test "separa dos jugadores superpuestos sin producir valores inválidos" do
    state = game()
    shared = %{state.players[1] | pos: {400.0, 300.0}, vel: {0.0, 0.0}}

    players =
      state.players |> Map.put(1, shared) |> Map.put(2, %{state.players[2] | pos: {400.0, 300.0}})

    next = Physics.step(%{state | players: players}, 0.016)
    {x1, y1} = next.players[1].pos
    {x2, y2} = next.players[2].pos
    distance = :math.sqrt(:math.pow(x2 - x1, 2) + :math.pow(y2 - y1, 2))

    assert distance >= 51.9
    assert Enum.all?([x1, y1, x2, y2], &is_float/1)
  end

  test "el golpe cercano comunica impulso al disco" do
    state = game()
    player = %{state.players[1] | pos: {450.0, 300.0}}

    state =
      state
      |> put_in([:players, 1], player)
      |> put_in([:puck], %{pos: {492.0, 300.0}, vel: {0.0, 0.0}})
      |> Game.put_input(1, %{up: false, down: false, left: false, right: true, kick: true})

    next = Physics.step(state, 0.016)
    assert elem(next.puck.vel, 0) > 500
    assert next.kick_cooldowns[1] > 0
  end
end
