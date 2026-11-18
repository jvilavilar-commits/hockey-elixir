defmodule Hockey.Physics do
  @moduledoc """
  Física determinista expresada como funciones puras sobre mapas y tuplas.
  No conoce procesos, sockets ni estado global.
  """

  @width 1000.0
  @height 600.0
  @wall 24.0
  @player_radius 26.0
  @puck_radius 15.0
  @goal_top 210.0
  @goal_bottom 390.0
  @player_acceleration 1_650.0
  @player_max_speed 330.0
  @player_drag 0.86
  @puck_drag 0.993
  @kick_speed 720.0
  @kick_range 30.0
  @restitution 0.78

  def dimensions, do: %{width: @width, height: @height, wall: @wall}

  def spawn_position(1), do: {260.0, 235.0}
  def spawn_position(2), do: {260.0, 365.0}
  def spawn_position(3), do: {740.0, 235.0}
  def spawn_position(4), do: {740.0, 365.0}

  def step(game, dt) when is_number(dt) and dt > 0 do
    players =
      game.players
      |> move_players(game.inputs, dt)
      |> resolve_player_pairs()

    kicked_puck =
      game.puck
      |> move_puck(dt)
      |> collide_with_players(players)
      |> apply_kicks(players, game.inputs, game.kick_cooldowns)

    kicked_by = Map.get(kicked_puck, :kicked_by)
    puck = kicked_puck |> collide_with_walls() |> Map.delete(:kicked_by)

    cooldowns =
      Map.new(game.kick_cooldowns, fn {id, value} -> {id, max(value - dt, 0.0)} end)

    %{
      game
      | players: players,
        puck: puck,
        kick_cooldowns: update_kick_cooldowns(cooldowns, kicked_by)
    }
  end

  def goal_side(%{pos: {x, y}}) when y >= @goal_top and y <= @goal_bottom do
    cond do
      x < -@puck_radius -> :red
      x > @width + @puck_radius -> :blue
      true -> nil
    end
  end

  def goal_side(_), do: nil

  def reset_objects(game) do
    players =
      Map.new(game.players, fn {id, player} ->
        {id, %{player | pos: spawn_position(id), vel: {0.0, 0.0}}}
      end)

    %{game | players: players, puck: %{pos: {@width / 2, @height / 2}, vel: {0.0, 0.0}}}
  end

  defp move_players(players, inputs, dt) do
    Map.new(players, fn {id, player} ->
      input = Map.get(inputs, id, %{})
      dx = bool(input[:right]) - bool(input[:left])
      dy = bool(input[:down]) - bool(input[:up])
      {nx, ny} = normalize({dx, dy})
      {vx, vy} = player.vel

      velocity =
        {vx * @player_drag + nx * @player_acceleration * dt,
         vy * @player_drag + ny * @player_acceleration * dt}
        |> limit(@player_max_speed)

      {next_x, next_y} = add(player.pos, scale(velocity, dt))

      position =
        {clamp(next_x, @wall + @player_radius, @width - @wall - @player_radius),
         clamp(next_y, @wall + @player_radius, @height - @wall - @player_radius)}

      {id, %{player | pos: position, vel: velocity}}
    end)
  end

  defp move_puck(puck, dt) do
    velocity = scale(puck.vel, :math.pow(@puck_drag, dt * 60.0))
    %{puck | pos: add(puck.pos, scale(velocity, dt)), vel: velocity}
  end

  defp resolve_player_pairs(players) do
    ids = Map.keys(players) |> Enum.sort()

    for(a <- ids, b <- ids, a < b, do: {a, b})
    |> Enum.reduce(players, fn {a, b}, acc ->
      p1 = acc[a]
      p2 = acc[b]
      {next1, next2} = resolve_equal_circles(p1, p2, @player_radius * 2)
      acc |> Map.put(a, next1) |> Map.put(b, next2)
    end)
  end

  defp resolve_equal_circles(a, b, min_distance) do
    delta = sub(b.pos, a.pos)
    distance = magnitude(delta)

    if distance < min_distance do
      normal = if distance < 0.001, do: {1.0, 0.0}, else: scale(delta, 1.0 / distance)
      overlap = min_distance - max(distance, 0.001)
      a_pos = sub(a.pos, scale(normal, overlap / 2))
      b_pos = add(b.pos, scale(normal, overlap / 2))
      relative = dot(sub(b.vel, a.vel), normal)

      if relative < 0 do
        impulse = scale(normal, -relative * @restitution)
        {%{a | pos: a_pos, vel: sub(a.vel, impulse)}, %{b | pos: b_pos, vel: add(b.vel, impulse)}}
      else
        {%{a | pos: a_pos}, %{b | pos: b_pos}}
      end
    else
      {a, b}
    end
  end

  defp collide_with_players(puck, players) do
    Enum.reduce(players, puck, fn {_id, player}, current ->
      delta = sub(current.pos, player.pos)
      distance = magnitude(delta)
      min_distance = @player_radius + @puck_radius

      if distance < min_distance do
        normal = if distance < 0.001, do: {1.0, 0.0}, else: scale(delta, 1.0 / distance)
        position = add(player.pos, scale(normal, min_distance))
        relative = dot(sub(current.vel, player.vel), normal)

        velocity =
          if relative < 0,
            do: add(current.vel, scale(normal, -(1.0 + @restitution) * relative)),
            else: current.vel

        %{current | pos: position, vel: add(velocity, scale(player.vel, 0.16))}
      else
        current
      end
    end)
  end

  defp apply_kicks(puck, players, inputs, cooldowns) do
    Enum.reduce(players, puck, fn {id, player}, current ->
      close? = distance(player.pos, current.pos) <= @player_radius + @puck_radius + @kick_range
      ready? = Map.get(cooldowns, id, 0.0) <= 0.0

      if inputs[id][:kick] == true and close? and ready? do
        direction = kick_direction(player, current, inputs[id])

        current
        |> Map.put(:vel, add(scale(direction, @kick_speed), scale(player.vel, 0.35)))
        |> Map.put(:kicked_by, id)
      else
        current
      end
    end)
  end

  defp update_kick_cooldowns(cooldowns, id) when is_integer(id) do
    Map.put(cooldowns, id, 0.32)
  end

  defp update_kick_cooldowns(cooldowns, _), do: cooldowns

  defp kick_direction(player, puck, input) do
    toward_puck = normalize(sub(puck.pos, player.pos))

    input_direction =
      normalize({bool(input[:right]) - bool(input[:left]), bool(input[:down]) - bool(input[:up])})

    direction =
      if input_direction == {0.0, 0.0},
        do: toward_puck,
        else: normalize(add(scale(toward_puck, 0.65), scale(input_direction, 0.35)))

    if direction == {0.0, 0.0}, do: {1.0, 0.0}, else: direction
  end

  defp collide_with_walls(puck) do
    %{pos: {x, y}, vel: {vx, vy}} = puck
    in_goal_mouth? = y >= @goal_top and y <= @goal_bottom

    {x, vx} =
      cond do
        not in_goal_mouth? and x < @wall + @puck_radius ->
          {@wall + @puck_radius, abs(vx) * @restitution}

        not in_goal_mouth? and x > @width - @wall - @puck_radius ->
          {@width - @wall - @puck_radius, -abs(vx) * @restitution}

        true ->
          {x, vx}
      end

    {y, vy} =
      cond do
        y < @wall + @puck_radius ->
          {@wall + @puck_radius, abs(vy) * @restitution}

        y > @height - @wall - @puck_radius ->
          {@height - @wall - @puck_radius, -abs(vy) * @restitution}

        true ->
          {y, vy}
      end

    %{puck | pos: {x, y}, vel: {vx, vy}}
  end

  defp bool(true), do: 1.0
  defp bool(_), do: 0.0
  defp add({ax, ay}, {bx, by}), do: {ax + bx, ay + by}
  defp sub({ax, ay}, {bx, by}), do: {ax - bx, ay - by}
  defp scale({x, y}, value), do: {x * value, y * value}
  defp dot({ax, ay}, {bx, by}), do: ax * bx + ay * by
  defp magnitude(vector), do: :math.sqrt(dot(vector, vector))
  defp distance(a, b), do: magnitude(sub(a, b))
  defp clamp(value, minimum, maximum), do: min(max(value, minimum), maximum)

  defp normalize(vector) do
    case magnitude(vector) do
      value when value < 0.0001 -> {0.0, 0.0}
      value -> scale(vector, 1.0 / value)
    end
  end

  defp limit(vector, maximum) do
    case magnitude(vector) do
      value when value > maximum -> scale(vector, maximum / value)
      _ -> vector
    end
  end
end
