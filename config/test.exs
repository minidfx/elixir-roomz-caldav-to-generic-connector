import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :roomz_caldav_to_generic_connector, RoomzCaldavToGenericConnectorWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "sXjbY4+2+orrOXAQ2BlDZOgb4W9KA+LkQZLR/1wSYiDWyeKzMgRuI3FgYwYIzGnV",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
