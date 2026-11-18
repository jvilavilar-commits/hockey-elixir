defmodule Hockey.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    port = Application.fetch_env!(:hockey_2d, :port)

    children = [
      {DynamicSupervisor, strategy: :one_for_one, name: Hockey.PlayerSupervisor},
      Hockey.GameServer,
      {Bandit, plug: HockeyWeb.Router, scheme: :http, port: port}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Hockey.Supervisor)
  end
end
