defmodule Hockey.GameServerTest do
  use ExUnit.Case, async: false

  alias Hockey.GameServer

  setup do
    :ok = GameServer.reset_for_test()
    on_exit(fn -> GameServer.reset_for_test() end)
    :ok
  end

  test "coordina cuatro clientes, rechaza el quinto y reconecta por token" do
    sockets = for _ <- 1..4, do: spawn_socket()

    welcomes =
      sockets
      |> Enum.map(fn socket ->
        assert {:ok, welcome} = GameServer.connect(socket)
        welcome
      end)

    assert Enum.map(welcomes, & &1.player_id) == [1, 2, 3, 4]
    assert GameServer.snapshot().phase == "playing"
    assert GameServer.snapshot().connected_count == 4
    assert {:error, :room_full} = GameServer.connect(spawn_socket())

    Process.exit(Enum.at(sockets, 2), :kill)
    wait_until(fn -> GameServer.snapshot().phase == "paused" end)
    paused_time = GameServer.snapshot().time_left
    Process.sleep(40)
    assert_in_delta GameServer.snapshot().time_left, paused_time, 0.001

    replacement = spawn_socket()
    token = Enum.at(welcomes, 2).token
    assert {:ok, %{player_id: 3}} = GameServer.connect(replacement, token)
    wait_until(fn -> GameServer.snapshot().phase == "playing" end)
    assert GameServer.snapshot().connected_count == 4
  end

  defp spawn_socket do
    parent = self()
    spawn(fn -> socket_loop(parent) end)
  end

  defp socket_loop(parent) do
    receive do
      message ->
        send(parent, {:socket_message, self(), message})
        socket_loop(parent)
    end
  end

  defp wait_until(check, attempts \\ 30)
  defp wait_until(_check, 0), do: flunk("la condición asíncrona no se cumplió")

  defp wait_until(check, attempts) do
    if check.() do
      :ok
    else
      Process.sleep(10)
      wait_until(check, attempts - 1)
    end
  end
end
