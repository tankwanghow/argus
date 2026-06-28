import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :tugas, Tugas.Repo,
  username: "tugas",
  password: "nyhlisted",
  hostname: "localhost",
  database: "tugas_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :tugas, TugasWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "fesFuS5oU/CJtyfmFoQr8VvL9XwcGQbngJIjJ15XlUCa1jwPAPdStM910FFItRxa",
  server: false

# In test we don't send emails
config :tugas, Tugas.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

config :tugas, :uploads_dir, Path.join(System.tmp_dir!(), "tugas_uploads_test")

config :ex_unit, exclude: [external_api: true]

config :tugas, :holidays_fetcher, fn _country, _year, _region -> [] end

config :tugas, :nager_countries_fetcher, fn ->
  [
    %{code: "SG", name: "Singapore"},
    %{code: "JP", name: "Japan"},
    %{code: "GB", name: "United Kingdom"},
    %{code: "US", name: "United States"},
    %{code: "DE", name: "Germany"}
  ]
end
