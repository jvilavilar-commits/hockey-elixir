defmodule Hockey.GameServer do
  @moduledoc """
  Actor autoritativo de la sala única.

  Conserva el estado oficial, crea un `PlayerServer` por puesto, procesa los
  mensajes de entrada y transmite instantáneas a todos los WebSockets.
  """
  use GenServer
  require Logger

  alias Hockey.{Game, PlayerServer}

  @server __MODULE__

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: @server)

  def connect(socket_pid, token \\ nil),
    do: GenServer.call(@server, {:connect, socket_pid, token})

  def disconnect(socket_pid), do: GenServer.cast(@server, {:disconnect, socket_pid})
  def input(player_id, input), do: GenServer.cast(@server, {:input, player_id, input})
  def rematch(player_id), do: GenServer.cast(@server, {:rematch, player_id})
  def snapshot, do: GenServer.call(@server, :snapshot)
  @doc false
  def reset_for_test, do: GenServer.call(@server, :reset_for_test)

  @impl true
  def init(:ok) do
    tick_ms = Application.get_env(:hockey_2d, :tick_ms, 16)
    Process.send_after(self(), :tick, tick_ms)

    {:ok,
     %{
       game: Game.new(),
       slots: %{},
       monitors: %{},
       tick_ms: tick_ms,
       broadcast_every: Application.get_env(:hockey_2d, :broadcast_every, 3),
       tick_count: 0
     }}
  end

  @impl true
  def handle_call({:connect, socket_pid, token}, _from, state) do
    case reconnect_slot(state, socket_pid, token) do
      {:ok, id, next_state} ->
        reply = welcome(next_state, id)
        broadcast(next_state)
        {:reply, {:ok, reply}, next_state}

      :not_found ->
        case first_available_id(state.slots) do
          nil ->
            {:reply, {:error, :room_full}, state}

          id ->
            {:ok, player_pid} =
              DynamicSupervisor.start_child(
                Hockey.PlayerSupervisor,
                {PlayerServer, id: id, socket_pid: socket_pid}
              )

            session_token = generate_token()
            monitor = Process.monitor(socket_pid)

            slot = %{
              player_pid: player_pid,
              socket_pid: socket_pid,
              token: session_token,
              monitor: monitor
            }

            next_state =
              state
              |> put_in([:slots, id], slot)
              |> put_in([:monitors, monitor], id)
              |> Map.update!(:game, &Game.add_player(&1, id))

            broadcast(next_state)
            {:reply, {:ok, welcome(next_state, id)}, next_state}
        end
    end
  end

  def handle_call(:snapshot, _from, state), do: {:reply, Game.public_state(state.game), state}

  def handle_call(:reset_for_test, _from, state) do
    Enum.each(state.slots, fn {_id, slot} ->
      if slot.monitor, do: Process.demonitor(slot.monitor, [:flush])
      DynamicSupervisor.terminate_child(Hockey.PlayerSupervisor, slot.player_pid)
    end)

    {:reply, :ok, %{state | game: Game.new(), slots: %{}, monitors: %{}, tick_count: 0}}
  end

  @impl true
  def handle_cast({:input, id, input}, state) do
    case state.slots[id] do
      %{player_pid: player_pid, socket_pid: socket_pid} when socket_pid != nil ->
        PlayerServer.input(player_pid, input)
        {:noreply, state}

      _ ->
        {:noreply, state}
    end
  end

  def handle_cast({:player_input, id, input}, state) do
    {:noreply, Map.update!(state, :game, &Game.put_input(&1, id, input))}
  end

  def handle_cast({:disconnect, socket_pid}, state) do
    {:noreply, mark_disconnected(state, socket_pid)}
  end

  def handle_cast({:rematch, id}, state) do
    if connected_player?(state, id) do
      next_state = Map.update!(state, :game, &Game.rematch/1)
      broadcast(next_state)
      {:noreply, next_state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:tick, state) do
    dt = state.tick_ms / 1_000
    game = Game.tick(state.game, dt)
    count = state.tick_count + 1
    next_state = %{state | game: game, tick_count: count}

    if rem(count, state.broadcast_every) == 0, do: broadcast(next_state)
    Process.send_after(self(), :tick, state.tick_ms)
    {:noreply, next_state}
  end

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state) do
    case state.monitors[monitor] do
      nil -> {:noreply, state}
      id -> {:noreply, mark_disconnected_by_id(state, id, monitor)}
    end
  end

  defp reconnect_slot(_state, _socket_pid, token) when token in [nil, ""], do: :not_found

  defp reconnect_slot(state, socket_pid, token) do
    case Enum.find(state.slots, fn {_id, slot} -> slot.token == token end) do
      nil ->
        :not_found

      {id, slot} ->
        if slot.monitor, do: Process.demonitor(slot.monitor, [:flush])
        monitor = Process.monitor(socket_pid)
        PlayerServer.attach(slot.player_pid, socket_pid)
        updated_slot = %{slot | socket_pid: socket_pid, monitor: monitor}

        monitors =
          state.monitors
          |> Map.delete(slot.monitor)
          |> Map.put(monitor, id)

        next_state =
          state
          |> put_in([:slots, id], updated_slot)
          |> Map.put(:monitors, monitors)
          |> Map.update!(:game, &Game.set_connected(&1, id, true))

        {:ok, id, next_state}
    end
  end

  defp mark_disconnected(state, socket_pid) do
    case Enum.find(state.slots, fn {_id, slot} -> slot.socket_pid == socket_pid end) do
      nil -> state
      {id, slot} -> mark_disconnected_by_id(state, id, slot.monitor)
    end
  end

  defp mark_disconnected_by_id(state, id, monitor) do
    slot = state.slots[id]

    cond do
      is_nil(slot) or slot.monitor != monitor ->
        state

      state.game.phase == :waiting ->
        if monitor, do: Process.demonitor(monitor, [:flush])
        DynamicSupervisor.terminate_child(Hockey.PlayerSupervisor, slot.player_pid)

        next_state = %{
          state
          | slots: Map.delete(state.slots, id),
            monitors: Map.delete(state.monitors, monitor),
            game: Game.remove_player(state.game, id)
        }

        broadcast(next_state)
        next_state

      true ->
        if monitor, do: Process.demonitor(monitor, [:flush])
        PlayerServer.detach(slot.player_pid)
        updated_slot = %{slot | socket_pid: nil, monitor: nil}

        next_state = %{
          state
          | slots: Map.put(state.slots, id, updated_slot),
            monitors: Map.delete(state.monitors, monitor),
            game: Game.set_connected(state.game, id, false)
        }

        broadcast(next_state)
        next_state
    end
  end

  defp broadcast(state) do
    payload = state.game |> Game.public_state() |> Jason.encode!()

    Enum.each(state.slots, fn {_id, slot} ->
      if slot.socket_pid, do: send(slot.socket_pid, {:game_state, payload})
    end)
  end

  defp welcome(state, id) do
    slot = state.slots[id]

    %{
      type: "welcome",
      player_id: id,
      team: if(id <= 2, do: "blue", else: "red"),
      token: slot.token,
      state: Game.public_state(state.game)
    }
  end

  defp first_available_id(slots), do: Enum.find(1..4, &(not Map.has_key?(slots, &1)))
  defp connected_player?(state, id), do: get_in(state.slots, [id, :socket_pid]) != nil
  defp generate_token, do: :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)
end
