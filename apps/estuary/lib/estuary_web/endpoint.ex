defmodule EstuaryWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :estuary

  @session_options [
    store: :cookie,
    key: "_estuary_key",
    signing_salt: "WQnXwowgt4JM5bQxei4smr2w"
  ]

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])

  plug(PlugHeartbeat, path: "/healthcheck")

  plug(Plug.Static,
    at: "/",
    from: :estuary,
    gzip: false,
    only: ~w(css fonts images js favicon.ico robots.txt)
  )

  if code_reloading? do
    socket("/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket)
    plug(Phoenix.LiveReloader)
    plug(Phoenix.CodeReloader)
  end

  plug(Plug.RequestId)

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  plug(Plug.Session, @session_options)

  plug(EstuaryWeb.Router)
end
