# SPDX-License-Identifier: PMPL-1.0-or-later

import Config

# VeriSimDB for development — local instance on default port.
config :burble, Burble.Store,
  url: "http://localhost:8080",
  auth: :none,
  timeout: 30_000

config :burble, BurbleWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 6473],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "dev_only_secret_key_base_that_must_be_replaced_in_production_with_real_secret",
  watchers: []

config :burble, dev_routes: true

config :logger, :console, format: "[$level] $message\n"
config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime

# Use Swoosh local adapter in dev (no hackney needed)
config :swoosh, :api_client, false
config :burble, Burble.Mailer, adapter: Swoosh.Adapters.Local
