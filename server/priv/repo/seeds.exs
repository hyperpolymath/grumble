# SPDX-License-Identifier: PMPL-1.0-or-later
# Seeds for development — creates a test user via VeriSimDB.

alias Burble.Auth

case Auth.register_user(%{
  email: "dev@burble.local",
  display_name: "Dev User",
  password: "burble_dev_123"
}) do
  {:ok, _user} -> IO.puts("Created dev user: dev@burble.local / burble_dev_123")
  {:error, _} -> IO.puts("Dev user may already exist (check VeriSimDB)")
end
