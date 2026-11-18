defmodule HockeyWeb.Router do
  @moduledoc false
  use Plug.Router

  plug(Plug.Logger)

  plug(Plug.Static,
    at: "/",
    from: {:hockey_2d, "priv/static"},
    gzip: false,
    only: ~w(assets favicon.ico)
  )

  plug(:match)
  plug(:dispatch)

  get "/socket" do
    conn = Plug.Conn.fetch_query_params(conn)

    conn
    |> WebSockAdapter.upgrade(HockeyWeb.Socket, %{token: conn.params["token"]}, timeout: 60_000)
    |> halt()
  end

  get "/health" do
    send_resp(conn, 200, "ok")
  end

  get "/" do
    path = Application.app_dir(:hockey_2d, "priv/static/index.html")
    send_file(conn, 200, path)
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end
end
