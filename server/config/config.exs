# SPDX-License-Identifier: PMPL-1.0-or-later
#
# Burble server configuration.

import Config

config :burble, BurbleWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: BurbleWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Burble.PubSub,
  live_view: [signing_salt: "burble_lv"]

# VeriSimDB persistent store
config :burble, Burble.Store,
  url: "http://localhost:8080",
  auth: :none,
  timeout: 30_000

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

# Rate limiting
config :hammer,
  backend: {Hammer.Backend.ETS, [expiry_ms: 60_000 * 60, cleanup_interval_ms: 60_000 * 10]}

import_config "#{config_env()}.exs"
