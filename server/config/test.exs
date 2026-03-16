# SPDX-License-Identifier: PMPL-1.0-or-later

import Config

# VeriSimDB for tests — use a separate port or test instance if available.
config :burble, Burble.Store,
  url: "http://localhost:8081",
  auth: :none,
  timeout: 10_000

config :burble, BurbleWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "test_only_secret_key_base_for_testing_purposes_only_do_not_use_in_production",
  server: false

config :logger, level: :warning
config :phoenix, :plug_init_mode, :runtime
config :bcrypt_elixir, :log_rounds, 1
