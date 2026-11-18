defmodule Hockey.Game do
  @moduledoc """
  Estado inmutable y reglas puras de una partida.

  Todas las transiciones devuelven un mapa nuevo; el `GameServer` se limita a
  programar ticks, recibir mensajes y difundir el resultado.
  """

  alias Hockey.Physics

  @match_seconds 180.0
  @goal_pause_seconds 1.15

  def new do
    %{
      phase: :waiting,
      players: %{},
      inputs: %{},
      connected: %{},
      puck: %{pos: {500.0, 300.0}, vel: {0.0, 0.0}},
      score: %{blue: 0, red: 0},
      time_left: @match_seconds,
      kick_cooldowns: %{},
      goal_pause: 0.0,
      last_goal: nil,
      winner: nil,
      revision: 0
    }
  end

  def add_player(game, id) when id in 1..4 do
    team = if id <= 2, do: :blue, else: :red

    player = %{
      id: id,
      number: if(id <= 2, do: id, else: id - 2),
      team: team,
      pos: Physics.spawn_position(id),
      vel: {0.0, 0.0}
    }

    game
    |> put_in([:players, id], player)
    |> put_in([:inputs, id], neutral_input())
    |> put_in([:connected, id], true)
    |> put_in([:kick_cooldowns, id], 0.0)
    |> maybe_start()
  end

  def remove_player(game, id) do
    game
    |> update_in([:players], &Map.delete(&1, id))
    |> update_in([:inputs], &Map.delete(&1, id))
    |> update_in([:connected], &Map.delete(&1, id))
    |> update_in([:kick_cooldowns], &Map.delete(&1, id))
    |> Map.put(:phase, :waiting)
  end

  def set_connected(game, id, connected?) do
    next = put_in(game, [:connected, id], connected?)

    cond do
      next.phase in [:playing, :goal_pause] and not all_connected?(next) ->
        %{next | phase: :paused}

      next.phase == :paused and all_connected?(next) ->
        %{next | phase: if(next.goal_pause > 0, do: :goal_pause, else: :playing)}

      true ->
        next
    end
  end

  def put_input(game, id, input) when is_map(input) do
    if Map.has_key?(game.players, id), do: put_in(game, [:inputs, id], input), else: game
  end

  def tick(%{phase: :playing} = game, dt) do
    next = Physics.step(game, dt)

    case Physics.goal_side(next.puck) do
      nil -> advance_clock(next, dt)
      team -> score_goal(next, team)
    end
  end

  def tick(%{phase: :goal_pause} = game, dt) do
    remaining = max(game.goal_pause - dt, 0.0)

    if remaining <= 0 do
      %{game | phase: :playing, goal_pause: 0.0, last_goal: nil, revision: game.revision + 1}
    else
      %{game | goal_pause: remaining, revision: game.revision + 1}
    end
  end

  def tick(game, _dt), do: %{game | revision: game.revision + 1}

  def rematch(%{phase: :finished} = game) do
    if all_connected?(game) do
      game
      |> Map.merge(%{
        phase: :playing,
        score: %{blue: 0, red: 0},
        time_left: @match_seconds,
        goal_pause: 0.0,
        last_goal: nil,
        winner: nil,
        revision: game.revision + 1
      })
      |> Physics.reset_objects()
    else
      game
    end
  end

  def rematch(game), do: game

  def public_state(game) do
    %{
      type: "state",
      phase: Atom.to_string(game.phase),
      players:
        game.players
        |> Enum.sort_by(fn {id, _} -> id end)
        |> Map.new(fn {id, player} ->
          {Integer.to_string(id),
           %{
             id: player.id,
             number: player.number,
             team: Atom.to_string(player.team),
             x: elem(player.pos, 0),
             y: elem(player.pos, 1),
             connected: Map.get(game.connected, id, false)
           }}
        end),
      puck: %{x: elem(game.puck.pos, 0), y: elem(game.puck.pos, 1)},
      score: game.score,
      time_left: game.time_left,
      last_goal: game.last_goal && Atom.to_string(game.last_goal),
      winner: game.winner && Atom.to_string(game.winner),
      connected_count: Enum.count(game.connected, fn {_id, value} -> value end),
      revision: game.revision
    }
  end

  defp maybe_start(game) do
    if map_size(game.players) == 4 and all_connected?(game) do
      %{game | phase: :playing} |> Physics.reset_objects()
    else
      game
    end
  end

  defp all_connected?(game) do
    map_size(game.players) == 4 and Enum.all?(game.connected, fn {_id, value} -> value end)
  end

  defp advance_clock(game, dt) do
    remaining = max(game.time_left - dt, 0.0)

    if remaining <= 0 do
      winner =
        cond do
          game.score.blue > game.score.red -> :blue
          game.score.red > game.score.blue -> :red
          true -> :draw
        end

      %{game | phase: :finished, time_left: 0.0, winner: winner, revision: game.revision + 1}
    else
      %{game | time_left: remaining, revision: game.revision + 1}
    end
  end

  defp score_goal(game, team) do
    game
    |> update_in([:score, team], &(&1 + 1))
    |> Map.put(:phase, :goal_pause)
    |> Map.put(:goal_pause, @goal_pause_seconds)
    |> Map.put(:last_goal, team)
    |> Map.update!(:revision, &(&1 + 1))
    |> Physics.reset_objects()
  end

  defp neutral_input, do: %{up: false, down: false, left: false, right: false, kick: false}
end
