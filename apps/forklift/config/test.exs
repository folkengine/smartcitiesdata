use Mix.Config

config :logger, :level, :info

config :forklift,
  retry_count: 5,
  retry_initial_delay: 10,
  # To ensure that MessageWriter never starts while testing
  message_processing_cadence: 1_000_000_000,
  cache_processing_batch_size: 1_000,
  user: "foobar"

config :forklift, :brook,
  handlers: [Forklift.Event.Handler],
  storage: [
    module: Brook.Storage.Ets,
    init_arg: [
      namespace: "forklift:view"
    ]
  ]

config :forklift, :dead_letter,
  driver: [
    module: DeadLetter.Carrier.Test,
    init_args: []
  ]

config :prestige, base_url: "http://127.0.0.1:8080"