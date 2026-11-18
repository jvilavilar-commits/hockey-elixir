defmodule HockeyWeb.Socket do
  @moduledoc false
  @behaviour WebSock

  alias Hockey.GameServer

  @impl true
  def init(%{token: token}) do
    case GameServer.connect(self(), token) do
      {:ok, welcome} ->
        send(self(), {:welcome, Jason.encode!(welcome)})
        {:ok, %{player_id: welcome.player_id, joined?: true}}

      {:error, :room_full} ->
        send(self(), {:socket_error, Jason.encode!(%{type: "error", reason: "room_full"})})
        {:ok, %{player_id: nil, joined?: false}}
    end
  end

  @impl true
  def handle_in({message, [opcode: :text]}, %{joined?: true} = state) do
    with {:ok, decoded} <- Jason.decode(message) do
      case decoded["type"] do
        "input" -> GameServer.input(state.player_id, decoded["input"] || %{})
        "rematch" -> GameServer.rematch(state.player_id)
        _ -> :ok
      end
    end

    {:ok, state}
  end

  def handle_in(_frame, state), do: {:ok, state}

  @impl true
  def handle_info({:welcome, payload}, state), do: {:push, {:text, payload}, state}
  def handle_info({:socket_error, payload}, state), do: {:push, {:text, payload}, state}
  def handle_info({:game_state, payload}, state), do: {:push, {:text, payload}, state}
  def handle_info(_message, state), do: {:ok, state}

  @impl true
  def terminate(_reason, %{joined?: true}), do: GameServer.disconnect(self())
  def terminate(_reason, _state), do: :ok
end
