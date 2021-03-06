use Mix.Config

kafka_brokers = System.get_env("KAFKA_BROKERS")
live_view_salt = System.get_env("LIVEVIEW_SALT")

get_redix_args = fn host, password ->
  [host: host, password: password]
  |> Enum.filter(fn
    {_, nil} -> false
    {_, ""} -> false
    _ -> true
  end)
end

redix_args = get_redix_args.(System.get_env("REDIS_HOST"), System.get_env("REDIS_PASSWORD"))

endpoint =
  kafka_brokers
  |> String.split(",")
  |> Enum.map(&String.trim/1)
  |> Enum.map(fn entry -> String.split(entry, ":") end)
  |> Enum.map(fn [host, port] -> {String.to_atom(host), String.to_integer(port)} end)

config :andi, :brook,
  instance: :andi,
  driver: [
    module: Brook.Driver.Kafka,
    init_arg: [
      endpoints: endpoint,
      topic: "event-stream",
      group: "andi-event-stream",
      config: [
        begin_offset: :earliest
      ]
    ]
  ],
  handlers: [Andi.EventHandler],
  storage: [
    module: Brook.Storage.Redis,
    init_arg: [redix_args: redix_args, namespace: "andi:view"]
  ]

config :andi, AndiWeb.Endpoint,
  live_view: [
    signing_salt: live_view_salt
  ]

config :andi,
  secrets_endpoint: System.get_env("SECRETS_ENDPOINT"),
  dead_letter_topic: "streaming-dead-letters",
  kafka_endpoints: endpoint

config :andi, Andi.Repo,
  database: System.get_env("POSTGRES_DBNAME"),
  username: System.get_env("POSTGRES_USER"),
  password: System.get_env("POSTGRES_PASSWORD"),
  hostname: System.get_env("POSTGRES_HOST"),
  port: System.get_env("POSTGRES_PORT"),
  ssl: true,
  ssl_opts: [
    verify: :verify_peer,
    versions: [:"tlsv1.2"],
    cacertfile: System.get_env("CA_CERTFILE_PATH"),
    verify_fun: &:ssl_verify_hostname.verify_fun/3
  ]

config :telemetry_event,
  metrics_port: System.get_env("METRICS_PORT") |> String.to_integer(),
  add_poller: true,
  add_metrics: [:phoenix_endpoint_stop_duration, :dataset_total_count],
  metrics_options: [
    [
      metric_name: "dataset_info.gauge",
      tags: [:dataset_id, :dataset_title, :system_name, :source_type, :org_name],
      metric_type: :last_value
    ],
    [
      metric_name: "andi_login_success",
      tags: [:app],
      metric_type: :counter
    ],
    [
      metric_name: "andi_login_failure",
      tags: [:app],
      metric_type: :counter
    ]
  ]

config :andi, Andi.Scheduler,
  jobs: [
    {"0 0 1 * *", {Andi.Harvest.Harvester, :start_harvesting, []}}
  ]

config :andi, AndiWeb.Auth.TokenHandler,
  issuer: System.get_env("AUTH_JWT_ISSUER"),
  allowed_algos: ["RS256"],
  verify_issuer: true
