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
      For example: https://verisimdb:8080
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
  port = String.to_integer(System.get_env("PORT") || "4020")

  config :burble, BurbleWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  # Guardian JWT secret — use SECRET_KEY_BASE if GUARDIAN_SECRET not set.
  guardian_secret = System.get_env("GUARDIAN_SECRET") || secret_key_base

  config :burble, Burble.Auth.Guardian,
    secret_key: guardian_secret

  # Topology mode (override for production clusters).
  topology = System.get_env("BURBLE_TOPOLOGY") || "monarchic"

  config :burble, Burble.Topology,
    mode: String.to_existing_atom(topology)

  # Base URL for magic link emails and invite links.
  base_url = System.get_env("BURBLE_BASE_URL") || "https://#{host}"

  # CORS: restrict to the configured origin in production.
  # Accepts comma-separated list of origins, e.g. "https://app.burble.org,https://admin.burble.org"
  cors_origins =
    case System.get_env("BURBLE_CORS_ORIGINS") do
      nil -> "https://#{host}"
      origins -> String.split(origins, ",") |> Enum.map(&String.trim/1)
    end

  config :burble,
    base_url: base_url,
    cors_origins: cors_origins

  # SMTP configuration for magic link email delivery.
  # All four SMTP_* variables must be set for production email sending.
  # If not set, falls back to Swoosh.Adapters.Local (emails logged, not sent).
  smtp_host = System.get_env("SMTP_HOST")

  if smtp_host do
    smtp_port = String.to_integer(System.get_env("SMTP_PORT") || "587")
    smtp_user = System.get_env("SMTP_USER") || raise "SMTP_USER required when SMTP_HOST is set"
    smtp_pass = System.get_env("SMTP_PASS") || raise "SMTP_PASS required when SMTP_HOST is set"

    config :burble, Burble.Mailer,
      adapter: Swoosh.Adapters.SMTP,
      relay: smtp_host,
      port: smtp_port,
      username: smtp_user,
      password: smtp_pass,
      ssl: smtp_port == 465,
      tls: :if_available,
      auth: :always,
      retries: 2,
      no_mx_lookups: false
  end
end
