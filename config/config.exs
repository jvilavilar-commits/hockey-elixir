import Config

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :hockey_2d,
  port: String.to_integer(System.get_env("PORT", "4000")),
  tick_ms: 16,
  broadcast_every: 3
