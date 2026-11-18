defmodule Hockey.PlayerServer do
  @moduledoc """
  Proceso ligero que representa a un jugador conectado.

  Recibe la entrada del WebSocket y la reenvía por paso de mensajes al proceso de
  partida. La partida sigue siendo la única autoridad sobre posiciones y puntos.
  """
  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  def input(pid, input), do: GenServer.cast(pid, {:input, input})
  def attach(pid, socket_pid), do: GenServer.cast(pid, {:attach, socket_pid})
  def detach(pid), do: GenServer.cast(pid, :detach)

  @impl true
  def init(opts) do
    {:ok, %{id: opts[:id], socket_pid: opts[:socket_pid], input: neutral_input()}}
  end

  @impl true
  def handle_cast({:input, input}, state) do
    sanitized = sanitize(input)
    GenServer.cast(Hockey.GameServer, {:player_input, state.id, sanitized})
    {:noreply, %{state | input: sanitized}}
  end

  def handle_cast({:attach, socket_pid}, state) do
    GenServer.cast(Hockey.GameServer, {:player_input, state.id, neutral_input()})
    {:noreply, %{state | socket_pid: socket_pid, input: neutral_input()}}
  end

  def handle_cast(:detach, state) do
    GenServer.cast(Hockey.GameServer, {:player_input, state.id, neutral_input()})
    {:noreply, %{state | socket_pid: nil, input: neutral_input()}}
  end

  defp sanitize(input) when is_map(input) do
    %{
      up: input["up"] == true,
      down: input["down"] == true,
      left: input["left"] == true,
      right: input["right"] == true,
      kick: input["kick"] == true
    }
  end

  defp sanitize(_), do: neutral_input()
  defp neutral_input, do: %{up: false, down: false, left: false, right: false, kick: false}
end
