defmodule HockeyWeb.RouterTest do
  use ExUnit.Case, async: true
  import Plug.Test

  test "expone la interfaz y el endpoint de salud" do
    health = HockeyWeb.Router.call(conn(:get, "/health"), [])
    assert health.status == 200
    assert health.resp_body == "ok"

    index = HockeyWeb.Router.call(conn(:get, "/"), [])
    assert index.status == 200
    assert index.resp_body =~ "NEON RINK"
  end
end
