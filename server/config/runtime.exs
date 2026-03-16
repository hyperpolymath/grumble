# SPDX-License-Identifier: PMPL-1.0-or-later
#
# Runtime configuration — loaded at boot, reads environment variables.

import Config

if System.get_env("PHX_SERVER") do
  config :burble, BurbleWeb.Endpoint, server: true
end

if config_env() == :prod do
  verisimdb_url =
    System.get_env("VERISIMDB_URL") ||
      raise """
      environment variable VERISIMDB_URL is missing.
      For example: http://verisimdb:8080
      """

  verisimdb_auth =
    case System.get_env("VERISIMDB_API_KEY") do
      nil -> :none
      key -> {:api_key, key}
    end

  config :burble, Burble.Store,
    url: verisimdb_url,
    auth: verisimdb_auth,
    timeout: String.to_integer(System.get_env("VERISIMDB_TIMEOUT") || "30000")

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      Generate one with: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :burble, BurbleWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base
end
